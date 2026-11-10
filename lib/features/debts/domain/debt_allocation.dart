import '../../../core/database/app_database.dart';
import '../../../core/domain/debt_kind.dart';

/// Сколько из одного долга уже погашено.
class DebtAllocation {
  const DebtAllocation({required this.debt, required this.paid});

  final DebtTransaction debt;

  /// Погашено из этого долга (0…сумма долга).
  final int paid;

  int get remaining => debt.amount - paid;
  bool get isSettled => remaining <= 0;
  bool get isPartial => paid > 0 && !isSettled;
}

/// Разносит оплаты по долгам: оплата сначала гасит **самые старые** долги, постепенно.
///
/// Операции идут в порядке времени. Оплата закрывает старейший открытый долг, остаток
/// переходит к следующему. Если открытых долгов нет, остаток копится как предоплата
/// и сразу гасит следующий выданный долг. Сумма непогашенных остатков всегда равна
/// балансу должника (если он положительный).
///
/// Возвращает `id долга → разнесение`; удалённые операции пропускаются.
Map<String, DebtAllocation> allocatePayments(Iterable<DebtTransaction> transactions) {
  final ops = transactions.where((t) => t.deletedAt == null).toList()
    ..sort((a, b) {
      final byTime = a.occurredAt.compareTo(b.occurredAt);
      if (byTime != 0) return byTime;
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });

  final open = <_Open>[]; // очередь: старейший долг первым
  final all = <_Open>[];
  var credit = 0; // оплаты, для которых ещё не было долга

  for (final t in ops) {
    if (t.kind == DebtKind.debt) {
      final entry = _Open(t);
      all.add(entry);
      final used = credit < t.amount ? credit : t.amount;
      entry.paid += used;
      credit -= used;
      if (entry.paid < t.amount) open.add(entry);
    } else {
      var left = t.amount;
      while (left > 0 && open.isNotEmpty) {
        final head = open.first;
        final need = head.debt.amount - head.paid;
        final take = left < need ? left : need;
        head.paid += take;
        left -= take;
        if (head.paid >= head.debt.amount) open.removeAt(0);
      }
      credit += left;
    }
  }

  return {for (final e in all) e.debt.id: DebtAllocation(debt: e.debt, paid: e.paid)};
}

class _Open {
  _Open(this.debt);
  final DebtTransaction debt;
  int paid = 0;
}
