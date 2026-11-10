import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/fade_slide_in.dart';
import '../../../core/widgets/skeleton.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_summary.dart';
import 'balance_style.dart';
import 'debtor_avatar.dart';
import 'debts_providers.dart';

class DebtsPage extends ConsumerWidget {
  const DebtsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final summaries = ref.watch(debtorSummariesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabDebts)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.selectionClick();
          context.push(Routes.debtorNew);
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.addDebtor),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(debtorSummariesProvider),
        child: summaries.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [SkeletonList(itemCount: 5)],
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(32),
            children: [Text('$e', textAlign: TextAlign.center)],
          ),
          data: (all) => all.isEmpty ? const _EmptyBook() : _DebtorList(all: all),
        ),
      ),
    );
  }
}

class _DebtorList extends ConsumerWidget {
  const _DebtorList({required this.all});

  final List<DebtorSummary> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final filter = ref.watch(selectedDebtFilterProvider);
    final config = ref.watch(debtFilterConfigProvider);
    final visible = applyDebtFilter(all, filter, now: DateTime.now(), config: config);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _TotalCard(total: totalOwed(all))),
        SliverToBoxAdapter(child: _FilterBar(selected: filter)),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.debtsFilteredEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final s = visible[i];
                return FadeSlideIn(
                  key: ValueKey(s.debtor.id),
                  delay: Duration(milliseconds: i < 8 ? i * 40 : 0),
                  child: _DebtorTile(
                    summary: s,
                    overdue: isOverdue(s, DateTime.now(), config),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.debtsTotalLabel,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(end: total.toDouble()),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  '${formatAmount(value.round())} ${l10n.currencySum}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.selected});

  final DebtFilter selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    String label(DebtFilter f) => switch (f) {
          DebtFilter.all => l10n.filterAll,
          DebtFilter.overdue => l10n.filterOverdue,
          DebtFilter.large => l10n.filterLarge,
          DebtFilter.byDate => l10n.filterByDate,
        };

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final f in DebtFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label(f)),
                selected: selected == f,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  ref.read(selectedDebtFilterProvider.notifier).select(f);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DebtorTile extends StatelessWidget {
  const _DebtorTile({required this.summary, required this.overdue});

  final DebtorSummary summary;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final d = summary.debtor;
    final subtitle = [
      if (d.shopName != null) d.shopName!,
      if (summary.lastOperationAt != null)
        l10n.lastOperation(formatDate(summary.lastOperationAt!)),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(Routes.debtorDetails(d.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                DebtorAvatar(id: d.id, name: d.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name, style: theme.textTheme.titleMedium, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      balanceText(l10n, summary.balance),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: balanceColor(theme.colorScheme, summary.balance),
                      ),
                    ),
                    if (overdue)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.overdueBadge,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBook extends StatelessWidget {
  const _EmptyBook();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.menu_book_rounded, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(l10n.debtsEmptyTitle,
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          l10n.debtsEmptyHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
