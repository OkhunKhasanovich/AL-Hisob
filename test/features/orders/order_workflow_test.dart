import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/domain/order_status.dart';
import 'package:al_hisob/core/domain/product_unit.dart';
import 'package:al_hisob/features/catalog/domain/product_pricing.dart';
import 'package:al_hisob/features/orders/domain/order_models.dart';
import 'package:al_hisob/features/orders/domain/order_workflow.dart';

void main() {
  group('переходы статусов', () {
    test('основной путь шаг за шагом', () {
      for (var i = 0; i < orderHappyPath.length - 1; i++) {
        expect(canTransition(orderHappyPath[i], orderHappyPath[i + 1]), isTrue,
            reason: '${orderHappyPath[i].name} → ${orderHappyPath[i + 1].name}');
      }
    });

    test('нельзя перескакивать и возвращаться назад', () {
      expect(canTransition(OrderStatus.created, OrderStatus.picking), isFalse);
      expect(canTransition(OrderStatus.created, OrderStatus.delivered), isFalse);
      expect(canTransition(OrderStatus.accepted, OrderStatus.created), isFalse);
      expect(canTransition(OrderStatus.picking, OrderStatus.accepted), isFalse);
      expect(canTransition(OrderStatus.inTransit, OrderStatus.ready), isFalse);
      expect(canTransition(OrderStatus.delivered, OrderStatus.inTransit), isFalse);
    });

    test('отклонить можно только новый заказ', () {
      expect(canTransition(OrderStatus.created, OrderStatus.rejected), isTrue);
      for (final s in OrderStatus.values.where((s) => s != OrderStatus.created)) {
        expect(canTransition(s, OrderStatus.rejected), isFalse, reason: s.name);
      }
    });

    test('отменить можно до доставки, но не после', () {
      for (final s in [
        OrderStatus.created,
        OrderStatus.accepted,
        OrderStatus.picking,
        OrderStatus.ready,
        OrderStatus.inTransit,
      ]) {
        expect(canTransition(s, OrderStatus.cancelled), isTrue, reason: s.name);
      }
      for (final s in [OrderStatus.delivered, OrderStatus.closed]) {
        expect(canTransition(s, OrderStatus.cancelled), isFalse, reason: s.name);
      }
    });

    test('конечные статусы не имеют переходов', () {
      for (final s in [OrderStatus.closed, OrderStatus.rejected, OrderStatus.cancelled]) {
        expect(isFinalStatus(s), isTrue, reason: s.name);
        expect(nextStatuses(s), isEmpty);
      }
      expect(isFinalStatus(OrderStatus.delivered), isFalse);
    });

    test('нельзя перейти в тот же статус', () {
      for (final s in OrderStatus.values) {
        expect(canTransition(s, s), isFalse, reason: s.name);
      }
    });

    test('из любого статуса можно дойти до конечного (нет тупиков)', () {
      for (final start in OrderStatus.values) {
        var reachedFinal = isFinalStatus(start);
        final seen = <OrderStatus>{start};
        final queue = [start];
        while (queue.isNotEmpty && !reachedFinal) {
          final s = queue.removeLast();
          for (final n in nextStatuses(s)) {
            if (isFinalStatus(n)) reachedFinal = true;
            if (seen.add(n)) queue.add(n);
          }
        }
        expect(reachedFinal, isTrue, reason: start.name);
      }
    });
  });

  group('правка состава', () {
    test('только пока заказ не собирают', () {
      expect(canEditItems(OrderStatus.created), isTrue);
      expect(canEditItems(OrderStatus.accepted), isTrue);
      for (final s in [
        OrderStatus.picking,
        OrderStatus.ready,
        OrderStatus.inTransit,
        OrderStatus.delivered,
        OrderStatus.closed,
        OrderStatus.rejected,
        OrderStatus.cancelled,
      ]) {
        expect(canEditItems(s), isFalse, reason: s.name);
      }
    });
  });

  group('группы фильтров', () {
    test('каждый статус попадает ровно в одну группу, кроме «Все»', () {
      final groups = OrderGroup.values.where((g) => g != OrderGroup.all);
      for (final s in OrderStatus.values) {
        expect(groups.where((g) => inGroup(s, g)).length, 1, reason: s.name);
        expect(inGroup(s, OrderGroup.all), isTrue);
      }
    });

    test('состав групп', () {
      expect(inGroup(OrderStatus.created, OrderGroup.fresh), isTrue);
      expect(inGroup(OrderStatus.picking, OrderGroup.inProgress), isTrue);
      expect(inGroup(OrderStatus.inTransit, OrderGroup.inProgress), isTrue);
      expect(inGroup(OrderStatus.delivered, OrderGroup.delivered), isTrue);
      expect(inGroup(OrderStatus.closed, OrderGroup.closed), isTrue);
      expect(inGroup(OrderStatus.rejected, OrderGroup.cancelled), isTrue);
      expect(inGroup(OrderStatus.cancelled, OrderGroup.cancelled), isTrue);
    });
  });

  group('расчёт строки и суммы', () {
    test('без упаковки', () {
      expect(lineTotal(unitPrice: 500, quantity: 7), 3500);
      expect(lineTotal(unitPrice: 500, quantity: 0), 0);
    });

    test('упаковки по цене упаковки, остаток поштучно', () {
      int t(int q) => lineTotal(unitPrice: 12000, quantity: q, packSize: 24, packPrice: 250000);
      expect(t(24), 250000);
      expect(t(30), 250000 + 6 * 12000);
      expect(t(5), 5 * 12000);
      expect(t(100), 4 * 250000 + 4 * 12000);
    });

    test('неполные данные об упаковке игнорируются', () {
      expect(lineTotal(unitPrice: 100, quantity: 10, packSize: 5), 1000);
      expect(lineTotal(unitPrice: 100, quantity: 10, packPrice: 400), 1000);
      expect(lineTotal(unitPrice: 100, quantity: 10, packSize: 0, packPrice: 400), 1000);
    });

    test('packBreakdown', () {
      expect(packBreakdown(30, 24), (packs: 1, rest: 6));
      expect(packBreakdown(5, 24), (packs: 0, rest: 5));
      expect(packBreakdown(48, 24), (packs: 2, rest: 0));
      expect(packBreakdown(7, null), (packs: 0, rest: 7));
    });

    test('orderSum складывает строки', () {
      const a = OrderItemInput(name: 'A', unit: ProductUnit.piece, quantity: 2, unitPrice: 1000);
      const b = OrderItemInput(
          name: 'B', unit: ProductUnit.kg, quantity: 30, unitPrice: 12000, packSize: 24, packPrice: 250000);
      expect(a.lineTotal, 2000);
      expect(b.lineTotal, 250000 + 6 * 12000);
      expect(orderSum([a, b]), 2000 + 322000);
      expect(orderSum(const []), 0);
    });

    test('withQuantity меняет количество и пересчитывает', () {
      const b = OrderItemInput(
          name: 'B', unit: ProductUnit.piece, quantity: 1, unitPrice: 12000, packSize: 24, packPrice: 250000);
      expect(b.withQuantity(24).lineTotal, 250000);
      expect(b.withQuantity(24).name, 'B');
    });
  });
}
