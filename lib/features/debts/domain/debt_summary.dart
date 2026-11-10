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
    this.totalGiven = 0,
    this.totalPaid = 0,
    this.operationCount = 0,
  });

  final Debtor debtor;

  /// Нормализованные телефоны в порядке добавления.
  final List<String> phones;
  final int balance;

  /// Дата последней операции (по `occurredAt`); `null`, если операций нет.
  final DateTime? lastOperationAt;

  /// Всего выдано в долг за всё время.
  final int totalGiven;

  /// Всего получено оплатой за всё время.
  final int totalPaid;

  /// Число операций (выдач и оплат).
  final int operationCount;

  bool get hasDebt => balance > 0;

  /// Какая часть выданного уже возвращена, 0…1 (0, если ничего не выдавалось).
  double get paidShare => totalGiven <= 0 ? 0 : (totalPaid / totalGiven).clamp(0.0, 1.0);
}

/// Сколько календарных дней прошло от [last] до [now]: 0 — сегодня, 1 — вчера.
/// `null`, если даты нет. Время суток не учитывается.
int? daysSince(DateTime? last, DateTime now) {
  if (last == null) return null;
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(last.year, last.month, last.day)).inDays;
  return days < 0 ? 0 : days;
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
  var given = 0, paid = 0;
  for (final t in txs) {
    if (last == null || t.occurredAt.isAfter(last)) last = t.occurredAt;
    if (t.kind == DebtKind.debt) {
      given += t.amount;
    } else {
      paid += t.amount;
    }
  }
  final orderedPhones = [...phones]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return DebtorSummary(
    debtor: d,
    phones: [for (final p in orderedPhones) p.phone],
    balance: computeBalance(txs),
    lastOperationAt: last,
    totalGiven: given,
    totalPaid: paid,
    operationCount: txs.length,
  );
}
