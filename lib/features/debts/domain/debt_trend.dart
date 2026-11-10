import '../../../core/database/app_database.dart';
import '../../../core/domain/debt_kind.dart';

/// Динамика общего долга за последние [days] дней (по умолчанию — неделя).
///
/// «Общий долг» считается так же, как в карточке обзора: сумма положительных
/// балансов должников, переплаты не вычитаются. Поэтому последняя точка графика
/// всегда равна сумме, показанной в карточке.
class DebtTrend {
  const DebtTrend({required this.points});

  /// Общий долг на конец каждого дня, от старого дня к сегодняшнему.
  final List<int> points;

  int get days => points.length;
  int get first => points.isEmpty ? 0 : points.first;
  int get last => points.isEmpty ? 0 : points.last;

  /// Насколько изменился общий долг за период (в сумах).
  int get change => last - first;

  /// Нет ни одного дня с долгом — рисовать нечего.
  bool get isEmpty => points.every((p) => p == 0);

  /// Изменение в процентах от долга на начало периода.
  /// `null`, если в начале периода долга не было (процент не определён).
  double? get percent => first > 0 ? change / first * 100 : null;

  DebtTrendDirection get direction => change > 0
      ? DebtTrendDirection.up
      : change < 0
      ? DebtTrendDirection.down
      : DebtTrendDirection.flat;
}

enum DebtTrendDirection {
  /// Долги выросли — это плохо для кошелька торговца.
  up,

  /// Долги сократились.
  down,

  /// Без изменений.
  flat,
}

/// Считает [DebtTrend] за [days] календарных дней, заканчивая днём [now].
///
/// [transactions] — только действующие операции действующих должников.
/// Операции с датой позже сегодняшнего дня учитываются в последней точке,
/// чтобы она совпадала с общим долгом в карточке.
DebtTrend computeDebtTrend(
  Iterable<DebtTransaction> transactions, {
  required DateTime now,
  int days = defaultTrendDays,
}) {
  assert(days >= 2, 'для графика нужно хотя бы две точки');
  final sorted = transactions.where((t) => t.deletedAt == null).toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  final balances = <String, int>{};
  var total = 0;
  var next = 0;

  void apply(DebtTransaction t) {
    final before = balances[t.debtorId] ?? 0;
    final after = before + (t.kind == DebtKind.debt ? t.amount : -t.amount);
    balances[t.debtorId] = after;
    total += (after > 0 ? after : 0) - (before > 0 ? before : 0);
  }

  final points = <int>[];
  for (var i = 0; i < days; i++) {
    final isLast = i == days - 1;
    // Граница дня i — полночь следующего дня; конструктор сам учитывает переход на другой месяц и DST.
    final end = DateTime(now.year, now.month, now.day - (days - 1 - i) + 1);
    while (next < sorted.length && (isLast || sorted[next].occurredAt.isBefore(end))) {
      apply(sorted[next++]);
    }
    points.add(total);
  }
  return DebtTrend(points: points);
}

/// График недельный: 7 дней, заканчивая сегодняшним.
const defaultTrendDays = 7;

/// Подпись индекса: «+12%», «−5,4%», «0%». Меньше 10% — с десятой долей.
/// `null`, если процент не определён (долга в начале периода не было).
String? formatTrendPercent(DebtTrend trend) {
  final percent = trend.percent;
  if (percent == null) return null;
  if (trend.change == 0) return '0%';
  final sign = percent > 0 ? '+' : '−';
  final abs = percent.abs();
  if (abs > 999) return '$sign>999%';
  if (abs >= 10) return '$sign${abs.round()}%';
  // Совсем малое изменение показываем как 0,1%, а не «0%», раз долг всё же изменился.
  final tenths = (abs * 10).round().clamp(1, 99);
  final text = tenths % 10 == 0 ? '${tenths ~/ 10}' : (tenths / 10).toStringAsFixed(1);
  return '$sign$text%';
}
