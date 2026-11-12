import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/money.dart';
import '../domain/debt_filter.dart';
import 'debts_providers.dart';

String debtFilterLabel(AppLocalizations l10n, DebtFilter f) => switch (f) {
      DebtFilter.all => l10n.filterAll,
      DebtFilter.overdue => l10n.filterOverdue,
      DebtFilter.large => l10n.filterLarge,
      DebtFilter.byDate => l10n.filterByDate,
    };

IconData debtFilterIcon(DebtFilter f) => switch (f) {
      DebtFilter.all => Icons.view_list_rounded,
      DebtFilter.overdue => Icons.schedule_rounded,
      DebtFilter.large => Icons.trending_up_rounded,
      DebtFilter.byDate => Icons.event_rounded,
    };

/// Кнопка-воронка в конце строки поиска. Точка на значке — фильтр включён.
class DebtFilterButton extends ConsumerWidget {
  const DebtFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final active = ref.watch(selectedDebtFilterProvider) != DebtFilter.all;
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: l10n.filterTooltip,
      onPressed: () => showDebtFilterSheet(context),
      style: active ? IconButton.styleFrom(backgroundColor: scheme.primaryContainer) : null,
      icon: Badge(
        isLabelVisible: active,
        smallSize: 8,
        child: Icon(
          Icons.filter_alt_rounded,
          color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

Future<void> showDebtFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    // Поверх панели вкладок, а не под ней: панель не просвечивает и не перекрывает кнопки шторки.
    useRootNavigator: true,
    context: context,
    // Без isScrollControlled лист ограничен 9/16 экрана, и на невысоких телефонах
    // или при крупном шрифте пункты не помещались.
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _FilterSheet(),
  );
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  String _hint(AppLocalizations l10n, DebtFilter f, DebtFilterConfig config) => switch (f) {
        DebtFilter.all => l10n.filterAllHint,
        DebtFilter.overdue => l10n.filterOverdueHint(config.overdueDays),
        DebtFilter.large =>
          l10n.filterLargeHint('${formatAmount(config.largeDebtThreshold)} ${l10n.currencySum}'),
        DebtFilter.byDate => l10n.filterByDateHint,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final selected = ref.watch(selectedDebtFilterProvider);
    final config = ref.watch(debtFilterConfigProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.filterSheetTitle, style: theme.textTheme.titleMedium),
            ),
            for (final f in DebtFilter.values)
              ListTile(
                leading: Icon(debtFilterIcon(f)),
                title: Text(debtFilterLabel(l10n, f)),
                subtitle: Text(_hint(l10n, f, config)),
                trailing: selected == f
                    ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                    : const Icon(Icons.circle_outlined),
                selected: selected == f,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(selectedDebtFilterProvider.notifier).select(f);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
