import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_providers.dart';
import '../data/debtors_repository.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_summary.dart';
import '../domain/search/debtor_search.dart';

final debtorsRepositoryProvider = Provider<DebtorsRepository>(
  (ref) => DebtorsRepository(ref.watch(appDatabaseProvider)),
);

/// Все должники с балансами; обновляется при любых изменениях в БД.
final debtorSummariesProvider = StreamProvider<List<DebtorSummary>>(
  (ref) => ref.watch(debtorsRepositoryProvider).watchSummaries(),
);

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

/// Индекс пересобирается только при изменении данных, а не при каждой букве.
final debtSearchIndexProvider = Provider<DebtorSearchIndex?>((ref) {
  final all = ref.watch(debtorSummariesProvider).value;
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
  final all = ref.watch(debtorSummariesProvider).value;
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
