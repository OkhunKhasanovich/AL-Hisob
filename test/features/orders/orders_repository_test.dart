import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/database/sync_columns.dart';
import 'package:al_savdogar/core/domain/debt_kind.dart';
import 'package:al_savdogar/core/domain/order_status.dart';
import 'package:al_savdogar/core/domain/product_unit.dart';
import 'package:al_savdogar/features/debts/data/debtors_repository.dart';
import 'package:al_savdogar/features/orders/data/orders_repository.dart';
import 'package:al_savdogar/features/orders/domain/order_models.dart';

const _cola = OrderItemInput(
  productId: 'p-cola',
  name: 'Coca-Cola 1.5L',
  unit: ProductUnit.piece,
  quantity: 24,
  unitPrice: 12000,
  packSize: 24,
  packPrice: 250000,
);
const _rice = OrderItemInput(
  productId: 'p-rice',
  name: 'Рис',
  unit: ProductUnit.kg,
  quantity: 10,
  unitPrice: 15000,
);

void main() {
  late AppDatabase db;
  late OrdersRepository repo;
  late DebtorsRepository debtors;
  late String customer;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = OrdersRepository(db);
    debtors = DebtorsRepository(db);
    customer = await debtors.createDebtor(const DebtorInput(name: 'Alisher', phones: ['901234567']));
  });
  tearDown(() => db.close());

  Future<String> newOrder({List<OrderItemInput> items = const [_cola, _rice], String? comment}) =>
      repo.createOrder(
        customerId: customer,
        items: items,
        actorName: 'Baraka Trade',
        comment: comment,
      );

  Future<void> advance(String id, List<OrderStatus> path) async {
    for (final s in path) {
      await repo.changeStatus(id, s, actorName: 'Baraka Trade');
    }
  }

  group('создание', () {
    test('статус «Создан», сумма, номер, история, снимок позиций', () async {
      final id = await newOrder(comment: '  Привезти до обеда ');
      final d = (await repo.loadOrder(id))!;

      expect(d.order.status, OrderStatus.created);
      expect(d.order.number, 1);
      expect(d.order.total, 250000 + 150000);
      expect(d.order.paidAmount, 0);
      expect(d.order.comment, 'Привезти до обеда');
      expect(d.order.syncStatus, SyncStatus.pending);
      expect(d.order.id, hasLength(36));
      expect(d.customerName, 'Alisher');
      expect(d.items.map((i) => i.name), ['Coca-Cola 1.5L', 'Рис']);
      expect(d.items.map((i) => i.lineTotal), [250000, 150000]);
      expect(d.items.map((i) => i.position), [0, 1]);
      expect(d.history, hasLength(1));
      expect(d.history.single.status, OrderStatus.created);
      expect(d.history.single.actorName, 'Baraka Trade');
    });

    test('номера растут: 1, 2, 3', () async {
      final a = await newOrder();
      final b = await newOrder();
      final c = await newOrder();
      expect([for (final id in [a, b, c]) (await repo.loadOrder(id))!.order.number], [1, 2, 3]);
    });

    test('список: новые сверху, с именем покупателя и числом позиций', () async {
      await newOrder(items: const [_rice]);
      await newOrder();
      final list = await repo.loadSummaries();
      expect(list.map((s) => s.order.number), [2, 1]);
      expect(list.map((s) => s.itemCount), [2, 1]);
      expect(list.first.customerName, 'Alisher');
    });

    test('невалидные данные отклоняются, ничего не записывается', () async {
      Future<void> create(List<OrderItemInput> items, {String? cust}) =>
          repo.createOrder(customerId: cust ?? customer, items: items, actorName: 'x');

      await expectLater(create(const []), throwsArgumentError);
      await expectLater(create([_rice.withQuantity(0)]), throwsArgumentError);
      await expectLater(create(const [OrderItemInput(name: 'A', unit: ProductUnit.piece, quantity: 1, unitPrice: 0)]),
          throwsArgumentError);
      await expectLater(create(const [OrderItemInput(name: ' ', unit: ProductUnit.piece, quantity: 1, unitPrice: 5)]),
          throwsArgumentError);
      await expectLater(create(const [_rice], cust: 'nobody'), throwsArgumentError);
      expect(await repo.loadSummaries(), isEmpty);
    });

    test('покупатель удалён из книги — старый заказ помнит имя', () async {
      final id = await newOrder();
      await debtors.deleteDebtor(customer);
      expect((await repo.loadOrder(id))!.customerName, 'Alisher');
      expect(
        () => repo.createOrder(customerId: customer, items: const [_rice], actorName: 'x'),
        throwsArgumentError,
        reason: 'новый заказ на удалённого нельзя',
      );
    });
  });

  group('правка состава', () {
    test('заменяет позиции, пересчитывает сумму, пишет «изменён» в историю', () async {
      final id = await newOrder();
      await repo.updateItems(
        id,
        [_rice.withQuantity(20)],
        actorName: 'Baraka Trade',
        comment: 'Только рис',
      );

      final d = (await repo.loadOrder(id))!;
      expect(d.items.map((i) => i.name), ['Рис']);
      expect(d.order.total, 300000);
      expect(d.order.comment, 'Только рис');
      expect(d.order.status, OrderStatus.created);
      expect(d.history.map((h) => h.isEdit), [false, true]);
      expect(d.history.last.status, OrderStatus.created);
      // Старые позиции остались в БД как удалённые (для синхронизации).
      expect((await db.select(db.orderItems).get()).where((i) => i.deletedAt != null), hasLength(2));
    });

    test('разрешена в «Создан» и «Принят», дальше — нет', () async {
      final id = await newOrder();
      await repo.changeStatus(id, OrderStatus.accepted, actorName: 'x');
      await repo.updateItems(id, [_rice], actorName: 'x');

      await repo.changeStatus(id, OrderStatus.picking, actorName: 'x');
      await expectLater(repo.updateItems(id, [_cola], actorName: 'x'), throwsStateError);
      expect((await repo.loadOrder(id))!.items.single.name, 'Рис');
    });

    test('невалидная правка не портит заказ', () async {
      final id = await newOrder();
      await expectLater(repo.updateItems(id, const [], actorName: 'x'), throwsArgumentError);
      final d = (await repo.loadOrder(id))!;
      expect(d.items, hasLength(2));
      expect(d.order.total, 400000);
    });
  });

  group('статусы и история', () {
    test('весь путь: каждый шаг пишется в историю с автором и временем', () async {
      final id = await newOrder();
      final path = [
        OrderStatus.accepted,
        OrderStatus.picking,
        OrderStatus.ready,
        OrderStatus.inTransit,
      ];
      await advance(id, path);
      await repo.deliver(id, paidAmount: 400000, actorName: 'Baraka Trade');
      await repo.changeStatus(id, OrderStatus.closed, actorName: 'Baraka Trade');

      final d = (await repo.loadOrder(id))!;
      expect(d.order.status, OrderStatus.closed);
      expect(d.history.map((h) => h.status), [
        OrderStatus.created,
        OrderStatus.accepted,
        OrderStatus.picking,
        OrderStatus.ready,
        OrderStatus.inTransit,
        OrderStatus.delivered,
        OrderStatus.closed,
      ]);
      expect(d.history.every((h) => h.actorName == 'Baraka Trade'), isTrue);
      final times = d.history.map((h) => h.createdAt).toList();
      expect(times, orderedEquals([...times]..sort()));
    });

    test('причина отклонения/отмены сохраняется в истории', () async {
      final a = await newOrder();
      await repo.changeStatus(a, OrderStatus.rejected, actorName: 'x', note: '  нет товара ');
      expect((await repo.loadOrder(a))!.history.last.note, 'нет товара');

      final b = await newOrder();
      await repo.changeStatus(b, OrderStatus.cancelled, actorName: 'x');
      expect((await repo.loadOrder(b))!.history.last.note, isNull);
    });

    test('недопустимый переход отклоняется и не меняет заказ', () async {
      final id = await newOrder();
      await expectLater(
        repo.changeStatus(id, OrderStatus.picking, actorName: 'x'),
        throwsA(isA<InvalidOrderTransition>()),
      );
      final d = (await repo.loadOrder(id))!;
      expect(d.order.status, OrderStatus.created);
      expect(d.history, hasLength(1));
    });

    test('из конечных статусов выхода нет', () async {
      final id = await newOrder();
      await repo.changeStatus(id, OrderStatus.rejected, actorName: 'x');
      for (final s in OrderStatus.values) {
        await expectLater(repo.changeStatus(id, s, actorName: 'x'), throwsA(anything), reason: s.name);
      }
    });

    test('«Доставлен» только через deliver()', () async {
      final id = await newOrder();
      await advance(id, [OrderStatus.accepted, OrderStatus.picking, OrderStatus.ready, OrderStatus.inTransit]);
      await expectLater(repo.changeStatus(id, OrderStatus.delivered, actorName: 'x'), throwsArgumentError);
    });

    test('несуществующий заказ', () async {
      await expectLater(repo.changeStatus('nope', OrderStatus.accepted, actorName: 'x'), throwsStateError);
    });
  });

  group('доставка и долг', () {
    Future<String> inTransit() async {
      final id = await newOrder(); // 400 000
      await advance(id, [OrderStatus.accepted, OrderStatus.picking, OrderStatus.ready, OrderStatus.inTransit]);
      return id;
    }

    Future<DebtorDetails> book() async => (await debtors.loadDetails(customer))!;

    test('оплачено полностью — долга в книге нет', () async {
      final id = await inTransit();
      await repo.deliver(id, paidAmount: 400000, actorName: 'x');

      final d = (await repo.loadOrder(id))!;
      expect(d.order.status, OrderStatus.delivered);
      expect(d.order.paidAmount, 400000);
      expect(d.remaining, 0);
      expect((await book()).transactions, isEmpty);
      expect((await book()).summary.balance, 0);
    });

    test('не оплачено — весь заказ записан долгом, привязка к заказу', () async {
      final id = await inTransit();
      await repo.deliver(id, paidAmount: 0, actorName: 'x');

      final tx = (await book()).transactions;
      expect(tx, hasLength(1));
      expect(tx.single.kind, DebtKind.debt);
      expect(tx.single.amount, 400000);
      expect(tx.single.orderId, id);
      expect(tx.single.comment, '#1');
      expect((await book()).summary.balance, 400000);
    });

    test('частичная оплата — долг на сумму заказа и оплата на полученное; баланс = остаток', () async {
      final id = await inTransit();
      await repo.deliver(id, paidAmount: 150000, actorName: 'x');

      final tx = (await book()).transactions;
      expect(tx.map((t) => t.kind).toSet(), {DebtKind.debt, DebtKind.payment});
      expect(tx.every((t) => t.orderId == id), isTrue);
      expect(tx.firstWhere((t) => t.kind == DebtKind.debt).amount, 400000);
      expect(tx.firstWhere((t) => t.kind == DebtKind.payment).amount, 150000);
      expect((await book()).summary.balance, 250000);
      expect((await repo.loadOrder(id))!.remaining, 250000);
    });

    test('долг не создаётся дважды', () async {
      final id = await inTransit();
      await repo.deliver(id, paidAmount: 100000, actorName: 'x');
      await expectLater(repo.deliver(id, paidAmount: 100000, actorName: 'x'),
          throwsA(isA<InvalidOrderTransition>()));
      await repo.changeStatus(id, OrderStatus.closed, actorName: 'x');

      expect((await book()).transactions, hasLength(2));
      expect((await book()).summary.balance, 300000);
    });

    test('оплата вне диапазона отклоняется, заказ остаётся «В пути»', () async {
      final id = await inTransit();
      await expectLater(repo.deliver(id, paidAmount: -1, actorName: 'x'), throwsArgumentError);
      await expectLater(repo.deliver(id, paidAmount: 400001, actorName: 'x'), throwsArgumentError);
      final d = (await repo.loadOrder(id))!;
      expect(d.order.status, OrderStatus.inTransit);
      expect(d.order.paidAmount, 0);
      expect((await book()).transactions, isEmpty);
    });

    test('доставить можно только заказ «В пути»', () async {
      final id = await newOrder();
      await expectLater(repo.deliver(id, paidAmount: 0, actorName: 'x'), throwsA(isA<InvalidOrderTransition>()));
    });

    test('несколько заказов одного покупателя суммируются в долге', () async {
      final a = await inTransit();
      final b = await inTransit();
      await repo.deliver(a, paidAmount: 0, actorName: 'x');
      await repo.deliver(b, paidAmount: 100000, actorName: 'x');
      expect((await book()).summary.balance, 400000 + 300000);
    });

    test('отменённый и отклонённый заказ долга не создают', () async {
      final a = await newOrder();
      await repo.changeStatus(a, OrderStatus.rejected, actorName: 'x');
      final b = await newOrder();
      await advance(b, [OrderStatus.accepted]);
      await repo.changeStatus(b, OrderStatus.cancelled, actorName: 'x');
      expect((await book()).transactions, isEmpty);
    });
  });

  group('потоки', () {
    test('watchSummaries и watchOrder обновляются при смене статуса', () async {
      final id = await newOrder();
      final lists = <OrderStatus>[];
      final details = <OrderStatus?>[];
      final s1 = repo.watchSummaries().listen((l) => lists.add(l.first.order.status));
      final s2 = repo.watchOrder(id).listen((d) => details.add(d?.order.status));
      addTearDown(() async {
        await s1.cancel();
        await s2.cancel();
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await repo.changeStatus(id, OrderStatus.accepted, actorName: 'x');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(lists.first, OrderStatus.created);
      expect(lists.last, OrderStatus.accepted);
      expect(details.last, OrderStatus.accepted);
    });
  });
}
