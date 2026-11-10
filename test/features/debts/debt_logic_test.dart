import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/database/sync_columns.dart';
import 'package:al_savdogar/core/domain/debt_kind.dart';
import 'package:al_savdogar/features/debts/domain/debt_filter.dart';
import 'package:al_savdogar/features/debts/domain/debt_summary.dart';

final _t0 = DateTime(2026, 1, 1);

Debtor _debtor(String id, String name, {DateTime? deletedAt}) => Debtor(
      id: id,
      createdAt: _t0,
      updatedAt: _t0,
      deletedAt: deletedAt,
      syncStatus: SyncStatus.pending,
      name: name,
    );

DebtTransaction _tx(
  String debtorId,
  DebtKind kind,
  int amount,
  DateTime at, {
  DateTime? deletedAt,
}) =>
    DebtTransaction(
      id: '$debtorId-$kind-$amount-${at.millisecondsSinceEpoch}',
      createdAt: at,
      updatedAt: at,
      deletedAt: deletedAt,
      syncStatus: SyncStatus.pending,
      debtorId: debtorId,
      kind: kind,
      amount: amount,
      occurredAt: at,
    );

DebtorPhone _phone(String debtorId, String phone, DateTime created) => DebtorPhone(
      id: '$debtorId-$phone',
      createdAt: created,
      updatedAt: created,
      syncStatus: SyncStatus.pending,
      debtorId: debtorId,
      phone: phone,
    );

void main() {
  final now = DateTime(2026, 6, 30, 12);

  group('computeBalance', () {
    test('нет операций — ноль', () => expect(computeBalance([]), 0));

    test('долги прибавляются, оплаты вычитаются', () {
      final txs = [
        _tx('a', DebtKind.debt, 1000000, DateTime(2026, 1, 2)),
        _tx('a', DebtKind.debt, 500000, DateTime(2026, 1, 3)),
        _tx('a', DebtKind.payment, 300000, DateTime(2026, 1, 4)),
      ];
      expect(computeBalance(txs), 1200000);
    });

    test('полная оплата даёт ноль, переплата — отрицательный баланс', () {
      expect(
        computeBalance([
          _tx('a', DebtKind.debt, 100, DateTime(2026, 1, 2)),
          _tx('a', DebtKind.payment, 100, DateTime(2026, 1, 3)),
        ]),
        0,
      );
      expect(
        computeBalance([
          _tx('a', DebtKind.debt, 100, DateTime(2026, 1, 2)),
          _tx('a', DebtKind.payment, 150, DateTime(2026, 1, 3)),
        ]),
        -50,
      );
    });

    test('удалённые операции не учитываются', () {
      final txs = [
        _tx('a', DebtKind.debt, 1000, DateTime(2026, 1, 2)),
        _tx('a', DebtKind.debt, 9999, DateTime(2026, 1, 3), deletedAt: DateTime(2026, 1, 4)),
      ];
      expect(computeBalance(txs), 1000);
    });
  });

  group('buildSummaries', () {
    test('считает баланс, последнюю операцию и порядок телефонов', () {
      final summaries = buildSummaries(
        debtors: [_debtor('a', 'Alisher'), _debtor('b', 'Bobur')],
        phones: [
          _phone('a', '+998902222222', DateTime(2026, 1, 2)),
          _phone('a', '+998901111111', DateTime(2026, 1, 1)),
        ],
        transactions: [
          _tx('a', DebtKind.debt, 500, DateTime(2026, 2, 1)),
          _tx('a', DebtKind.payment, 100, DateTime(2026, 3, 1)),
          _tx('b', DebtKind.debt, 70, DateTime(2026, 2, 10)),
        ],
      );
      final a = summaries.firstWhere((s) => s.debtor.id == 'a');
      expect(a.balance, 400);
      expect(a.lastOperationAt, DateTime(2026, 3, 1));
      expect(a.phones, ['+998901111111', '+998902222222']);
      expect(summaries.firstWhere((s) => s.debtor.id == 'b').balance, 70);
    });

    test('удалённые должники пропускаются; без операций — баланс 0', () {
      final summaries = buildSummaries(
        debtors: [_debtor('a', 'A', deletedAt: _t0), _debtor('b', 'B')],
        phones: const [],
        transactions: [_tx('a', DebtKind.debt, 5, _t0)],
      );
      expect(summaries, hasLength(1));
      expect(summaries.single.balance, 0);
      expect(summaries.single.lastOperationAt, isNull);
      expect(summaries.single.hasDebt, isFalse);
    });
  });

  group('фильтры', () {
    DebtorSummary s(String name, int balance, DateTime? last) => DebtorSummary(
          debtor: _debtor(name, name),
          phones: const [],
          balance: balance,
          lastOperationAt: last,
        );

    const config = DebtFilterConfig(overdueDays: 30, largeDebtThreshold: 1000000);

    test('просрочка: строго больше N дней, и только при наличии долга', () {
      expect(isOverdue(s('x', 100, now.subtract(const Duration(days: 30))), now, config),
          isFalse, reason: 'ровно 30 дней — ещё не просрочка');
      expect(
          isOverdue(
              s('x', 100, now.subtract(const Duration(days: 30, minutes: 1))), now, config),
          isTrue);
      expect(isOverdue(s('x', 0, now.subtract(const Duration(days: 90))), now, config),
          isFalse, reason: 'долга нет');
      expect(isOverdue(s('x', -10, now.subtract(const Duration(days: 90))), now, config),
          isFalse, reason: 'переплата');
      expect(isOverdue(s('x', 100, null), now, config), isFalse);
    });

    test('порог просрочки настраивается', () {
      final debtor = s('x', 100, now.subtract(const Duration(days: 10)));
      expect(isOverdue(debtor, now, const DebtFilterConfig(overdueDays: 7)), isTrue);
      expect(isOverdue(debtor, now, const DebtFilterConfig(overdueDays: 14)), isFalse);
    });

    test('крупный долг: не меньше порога', () {
      expect(isLargeDebt(s('x', 999999, null), config), isFalse);
      expect(isLargeDebt(s('x', 1000000, null), config), isTrue);
      expect(isLargeDebt(s('x', 5000000, null), config), isTrue);
    });

    final list = [
      s('Aziz', 500000, now.subtract(const Duration(days: 5))),
      s('Bobur', 2500000, now.subtract(const Duration(days: 60))),
      s('Davron', 0, now.subtract(const Duration(days: 100))),
      s('Eldor', 1500000, now.subtract(const Duration(days: 2))),
      s('Farrux', 300000, now.subtract(const Duration(days: 45))),
      s('Gulnora', 0, null),
    ];
    List<String> names(DebtFilter f) =>
        applyDebtFilter(list, f, now: now, config: config).map((e) => e.debtor.name).toList();

    test('все: по убыванию долга, при равенстве — по имени', () {
      expect(names(DebtFilter.all),
          ['Bobur', 'Eldor', 'Aziz', 'Farrux', 'Davron', 'Gulnora']);
    });

    test('просроченные', () {
      expect(names(DebtFilter.overdue), ['Bobur', 'Farrux']);
    });

    test('крупные', () {
      expect(names(DebtFilter.large), ['Bobur', 'Eldor']);
    });

    test('по дате: новые сверху, без операций — в конце', () {
      expect(names(DebtFilter.byDate),
          ['Eldor', 'Aziz', 'Farrux', 'Bobur', 'Davron', 'Gulnora']);
    });

    test('входной список не меняется', () {
      final before = list.map((e) => e.debtor.name).toList();
      applyDebtFilter(list, DebtFilter.all, now: now, config: config);
      expect(list.map((e) => e.debtor.name).toList(), before);
    });
  });

  test('totalOwed суммирует только положительные балансы', () {
    DebtorSummary s(int b) => DebtorSummary(
        debtor: _debtor('$b', '$b'), phones: const [], balance: b, lastOperationAt: null);
    expect(totalOwed([s(100), s(-40), s(0), s(250)]), 350);
    expect(totalOwed([]), 0);
  });
}
