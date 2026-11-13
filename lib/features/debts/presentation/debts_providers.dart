import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/settings_providers.dart';
import '../data/debtors_repository.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_summary.dart';
import '../domain/debt_trend.dart';
import '../domain/search/debtor_search.dart';

final debtorsRepositoryProvider = Provider<DebtorsRepository>(
  (ref) => DebtorsRepository(ref.watch(appDatabaseProvider)),
);

/// Все должники с балансами; обновляется при любых изменениях в БД.
final debtorSummariesProvider = StreamProvider<List<DebtorSummary>>(
  (ref) => ref.watch(debtorsRepositoryProvider).watchSummaries(),
);

/// Должники выбранной книги («мне должны» или «я должен»). Всё на экране «Долги»
/// (список, поиск, итоги, график) строится из них.
final sideSummariesProvider = Provider<AsyncValue<List<DebtorSummary>>>((ref) {
  final side = ref.watch(debtsSideProvider);
  return ref.watch(debtorSummariesProvider).whenData(
        (all) => [for (final s in all) if (s.debtor.direction == side) s],
      );
});

/// Карточка одного должника.
final debtorDetailsProvider = StreamProvider.autoDispose.family<DebtorDetails?, String>(
  (ref, id) => ref.watch(debtorsRepositoryProvider).watchDetails(id),
);

/// Выбранный фильтр списка.
class SelectedDebtFilter extends Notifier<DebtFilter> {
  @override
  DebtFilter build() => DebtFilter.all;

  void select(DebtFilter filter) => state = filter;
}

final selectedDebtFilterProvider =
    NotifierProvider<SelectedDebtFilter, DebtFilter>(SelectedDebtFilter.new);

/// Текст запроса (уже после debounce). Пусто — поиск выключен.
class DebtSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final debtSearchQueryProvider =
    NotifierProvider<DebtSearchQuery, String>(DebtSearchQuery.new);

/// Динамика общего долга за неделю; `null`, пока данные грузятся, или если долгов не было.
final debtTrendProvider = Provider<DebtTrend?>((ref) {
  final all = ref.watch(_activeTransactionsProvider).value;
  final side = ref.watch(sideSummariesProvider).value;
  if (all == null || side == null) return null;
  // Только операции должников выбранной книги: у «я должен» своя динамика.
  final ids = {for (final s in side) s.debtor.id};
  final txs = [for (final t in all) if (ids.contains(t.debtorId)) t];
  final trend = computeDebtTrend(txs, now: DateTime.now());
  return trend.isEmpty ? null : trend;
});

final _activeTransactionsProvider = StreamProvider<List<DebtTransaction>>(
  (ref) => ref.watch(debtorsRepositoryProvider).watchActiveTransactions(),
);

/// Индекс пересобирается только при изменении данных, а не при каждой букве.
final debtSearchIndexProvider = Provider<DebtorSearchIndex?>((ref) {
  final all = ref.watch(sideSummariesProvider).value;
  return all == null ? null : DebtorSearchIndex(all);
});

/// Строка списка: должник и, если нашли по номеру, какой именно телефон совпал.
class DebtorRow {
  const DebtorRow(this.summary, [this.matchedPhone]);

  final DebtorSummary summary;
  final String? matchedPhone;
}

/// Что показывать в списке: без запроса — отфильтрованный и отсортированный список;
/// с запросом — результаты поиска по релевантности, суженные выбранным фильтром.
final visibleDebtorsProvider = Provider<List<DebtorRow>?>((ref) {
  final all = ref.watch(sideSummariesProvider).value;
  if (all == null) return null;
  final filter = ref.watch(selectedDebtFilterProvider);
  final config = ref.watch(debtFilterConfigProvider);
  final query = ref.watch(debtSearchQueryProvider).trim();
  final now = DateTime.now();

  if (query.isEmpty) {
    return [for (final s in applyDebtFilter(all, filter, now: now, config: config)) DebtorRow(s)];
  }
  final hits = ref.watch(debtSearchIndexProvider)?.search(query) ?? const <SearchHit>[];
  return [
    for (final h in hits)
      if (matchesFilter(h.summary, filter, now: now, config: config))
        DebtorRow(h.summary, h.matchedPhone),
  ];
});
