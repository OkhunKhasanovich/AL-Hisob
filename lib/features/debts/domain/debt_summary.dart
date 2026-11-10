import '../../../core/database/app_database.dart';
import '../../../core/domain/debt_kind.dart';

/// Баланс = сумма выданных долгов − сумма полученных оплат.
/// Положительный — должник должен, отрицательный — переплата.
int computeBalance(Iterable<DebtTransaction> transactions) {
  var balance = 0;
  for (final t in transactions) {
    if (t.deletedAt != null) continue;
    balance += t.kind == DebtKind.debt ? t.amount : -t.amount;
  }
  return balance;
}

/// Должник вместе с вычисленными полями для списка.
class DebtorSummary {
  const DebtorSummary({
    required this.debtor,
    required this.phones,
    required this.balance,
    required this.lastOperationAt,
  });

  final Debtor debtor;

  /// Нормализованные телефоны в порядке добавления.
  final List<String> phones;
  final int balance;

  /// Дата последней операции (по `occurredAt`); `null`, если операций нет.
  final DateTime? lastOperationAt;

  bool get hasDebt => balance > 0;
}

/// Собирает сводки из «сырых» строк. Удалённые (soft delete) записи игнорируются.
List<DebtorSummary> buildSummaries({
  required Iterable<Debtor> debtors,
  required Iterable<DebtorPhone> phones,
  required Iterable<DebtTransaction> transactions,
}) {
  final phonesByDebtor = <String, List<DebtorPhone>>{};
  for (final p in phones) {
    if (p.deletedAt == null) (phonesByDebtor[p.debtorId] ??= []).add(p);
  }
  final txByDebtor = <String, List<DebtTransaction>>{};
  for (final t in transactions) {
    if (t.deletedAt == null) (txByDebtor[t.debtorId] ??= []).add(t);
  }

  return [
    for (final d in debtors)
      if (d.deletedAt == null)
        _summarize(d, phonesByDebtor[d.id] ?? const [], txByDebtor[d.id] ?? const []),
  ];
}

DebtorSummary _summarize(Debtor d, List<DebtorPhone> phones, List<DebtTransaction> txs) {
  DateTime? last;
  for (final t in txs) {
    if (last == null || t.occurredAt.isAfter(last)) last = t.occurredAt;
  }
  final orderedPhones = [...phones]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return DebtorSummary(
    debtor: d,
    phones: [for (final p in orderedPhones) p.phone],
    balance: computeBalance(txs),
    lastOperationAt: last,
  );
}
