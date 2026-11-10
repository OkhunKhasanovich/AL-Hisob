import 'debt_summary.dart';

enum DebtFilter {
  /// Все должники, по убыванию долга.
  all,

  /// Есть долг и давно не было операций.
  overdue,

  /// Долг не меньше порога.
  large,

  /// Все должники, по дате последней операции (новые сверху).
  byDate,
}

/// Настройки, влияющие на фильтры.
class DebtFilterConfig {
  const DebtFilterConfig({
    this.overdueDays = defaultOverdueDays,
    this.largeDebtThreshold = defaultLargeDebtThreshold,
  });

  static const defaultOverdueDays = 30;
  static const defaultLargeDebtThreshold = 1000000;

  final int overdueDays;
  final int largeDebtThreshold;
}

/// Должник просрочен, если у него есть долг и с последней операции
/// (выдачи долга или оплаты) прошло **больше** [DebtFilterConfig.overdueDays] дней.
bool isOverdue(DebtorSummary s, DateTime now, DebtFilterConfig config) {
  final last = s.lastOperationAt;
  if (!s.hasDebt || last == null) return false;
  return now.difference(last) > Duration(days: config.overdueDays);
}

bool isLargeDebt(DebtorSummary s, DebtFilterConfig config) =>
    s.balance >= config.largeDebtThreshold;

/// Подходит ли должник под [filter] как под ограничение (без сортировки).
/// «Все» и «По дате» никого не исключают: это порядок, а не отбор.
/// Используется, чтобы сузить результаты поиска, не меняя их порядок по релевантности.
bool matchesFilter(
  DebtorSummary s,
  DebtFilter filter, {
  required DateTime now,
  DebtFilterConfig config = const DebtFilterConfig(),
}) =>
    switch (filter) {
      DebtFilter.all || DebtFilter.byDate => true,
      DebtFilter.overdue => isOverdue(s, now, config),
      DebtFilter.large => isLargeDebt(s, config),
    };

/// Применяет фильтр и сортировку. Не изменяет входной список.
List<DebtorSummary> applyDebtFilter(
  Iterable<DebtorSummary> all,
  DebtFilter filter, {
  required DateTime now,
  DebtFilterConfig config = const DebtFilterConfig(),
}) {
  int byBalanceDesc(DebtorSummary a, DebtorSummary b) {
    final c = b.balance.compareTo(a.balance);
    return c != 0 ? c : _byName(a, b);
  }

  switch (filter) {
    case DebtFilter.all:
      return all.toList()..sort(byBalanceDesc);
    case DebtFilter.overdue:
      return all.where((s) => isOverdue(s, now, config)).toList()..sort(byBalanceDesc);
    case DebtFilter.large:
      return all.where((s) => isLargeDebt(s, config)).toList()..sort(byBalanceDesc);
    case DebtFilter.byDate:
      return all.toList()
        ..sort((a, b) {
          final x = a.lastOperationAt, y = b.lastOperationAt;
          if (x == null && y == null) return _byName(a, b);
          if (x == null) return 1; // без операций — в конец
          if (y == null) return -1;
          final c = y.compareTo(x);
          return c != 0 ? c : _byName(a, b);
        });
  }
}

int _byName(DebtorSummary a, DebtorSummary b) =>
    a.debtor.name.toLowerCase().compareTo(b.debtor.name.toLowerCase());

/// Общий долг: сумма положительных балансов (переплаты не вычитаются).
int totalOwed(Iterable<DebtorSummary> all) =>
    all.fold(0, (sum, s) => s.balance > 0 ? sum + s.balance : sum);

/// Сводка по всей книге для верхней карточки.
class DebtsOverview {
  const DebtsOverview({
    required this.totalOwed,
    required this.debtorCount,
    required this.overdueCount,
    required this.overdueAmount,
  });

  /// Сумма всех долгов (переплаты не вычитаются).
  final int totalOwed;

  /// Сколько должников сейчас должны (баланс > 0).
  final int debtorCount;

  final int overdueCount;
  final int overdueAmount;
}

DebtsOverview computeOverview(
  Iterable<DebtorSummary> all, {
  required DateTime now,
  DebtFilterConfig config = const DebtFilterConfig(),
}) {
  var owed = 0, debtors = 0, overdueCount = 0, overdueAmount = 0;
  for (final s in all) {
    if (!s.hasDebt) continue;
    owed += s.balance;
    debtors++;
    if (isOverdue(s, now, config)) {
      overdueCount++;
      overdueAmount += s.balance;
    }
  }
  return DebtsOverview(
    totalOwed: owed,
    debtorCount: debtors,
    overdueCount: overdueCount,
    overdueAmount: overdueAmount,
  );
}
