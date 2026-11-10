import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_providers.dart';
import '../data/debtors_repository.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_summary.dart';

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
