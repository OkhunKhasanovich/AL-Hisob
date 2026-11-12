import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/database/sync_columns.dart';
import 'package:al_hisob/core/domain/debt_kind.dart';
import 'package:al_hisob/features/debts/domain/debt_allocation.dart';
import 'package:al_hisob/features/debts/domain/debt_summary.dart';

int _n = 0;

DebtTransaction _tx(DebtKind kind, int amount, DateTime at, {DateTime? deletedAt}) {
  _n++;
  return DebtTransaction(
    id: 't$_n',
    createdAt: at,
    updatedAt: at,
    deletedAt: deletedAt,
    syncStatus: SyncStatus.pending,
    debtorId: 'd',
    kind: kind,
    amount: amount,
    occurredAt: at,
  );
}

void main() {
  DateTime day(int d) => DateTime(2026, 6, d, 12);
  DebtTransaction debt(int amount, int d) => _tx(DebtKind.debt, amount, day(d));
  DebtTransaction pay(int amount, int d) => _tx(DebtKind.payment, amount, day(d));

  group('allocatePayments: оплата гасит самые старые долги первыми', () {
    test('частичная оплата уходит в старейший долг', () {
      final d1 = debt(1000, 1), d2 = debt(500, 5);
      final a = allocatePayments([d2, d1, pay(400, 10)]);
      expect(a[d1.id]!.paid, 400);
      expect(a[d1.id]!.remaining, 600);
      expect(a[d1.id]!.isPartial, isTrue);
      expect(a[d2.id]!.paid, 0, reason: 'новый долг ждёт своей очереди');
    });

    test('оплата переходит со старого долга на следующий постепенно', () {
      final d1 = debt(1000, 1), d2 = debt(500, 5), d3 = debt(300, 8);
      final a = allocatePayments([d1, d2, d3, pay(1200, 10)]);
      expect(a[d1.id]!.isSettled, isTrue);
      expect(a[d2.id]!.paid, 200);
      expect(a[d2.id]!.remaining, 300);
      expect(a[d3.id]!.paid, 0);
    });

    test('несколько оплат складываются по порядку', () {
      final d1 = debt(1000, 1), d2 = debt(500, 2);
      final a = allocatePayments([d1, d2, pay(600, 3), pay(600, 4)]);
      expect(a[d1.id]!.isSettled, isTrue);
      expect(a[d2.id]!.paid, 200);
    });

    test('полная оплата закрывает все долги', () {
      final d1 = debt(1000, 1), d2 = debt(500, 5);
      final a = allocatePayments([d1, d2, pay(1500, 6)]);
      expect(a.values.every((e) => e.isSettled), isTrue);
    });

    test('оплата до долга копится и гасит следующий выданный долг', () {
      final d1 = debt(700, 5);
      final a = allocatePayments([pay(300, 1), d1]);
      expect(a[d1.id]!.paid, 300);
      expect(a[d1.id]!.remaining, 400);
    });

    test('оплата больше всех долгов: все погашены, лишнее — переплата', () {
      final d1 = debt(100, 1);
      final a = allocatePayments([d1, pay(900, 2)]);
      expect(a[d1.id]!.isSettled, isTrue);
      expect(a[d1.id]!.paid, 100, reason: 'не больше суммы долга');
    });

    test('удалённые операции пропускаются', () {
      final d1 = debt(1000, 1);
      final a = allocatePayments([d1, _tx(DebtKind.payment, 1000, day(2), deletedAt: day(3))]);
      expect(a[d1.id]!.paid, 0);
    });

    test('порядок во входном списке не важен: важно время операций', () {
      final d1 = debt(1000, 1), d2 = debt(1000, 2), p = pay(1000, 3);
      final a = allocatePayments([p, d2, d1]);
      expect(a[d1.id]!.isSettled, isTrue);
      expect(a[d2.id]!.paid, 0);
    });

    test('сумма остатков равна положительному балансу должника', () {
      final txs = [debt(1000, 1), debt(500, 3), pay(700, 4), debt(250, 6), pay(100, 7)];
      final a = allocatePayments(txs);
      final remaining = a.values.fold<int>(0, (s, e) => s + e.remaining);
      expect(remaining, computeBalance(txs));
    });
  });
}
