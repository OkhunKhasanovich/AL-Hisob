import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/debounced_search_field.dart';
import '../../../core/widgets/fade_slide_in.dart';
import '../../../core/widgets/section_app_bar.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/presentation/login_prompt.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_summary.dart';
import 'debt_filter_sheet.dart';
import 'debtor_tile.dart';
import 'debts_overview_card.dart';
import 'debts_providers.dart';
import '../../shell/glass_nav_bar.dart';

class DebtsPage extends ConsumerWidget {
  const DebtsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final summaries = ref.watch(debtorSummariesProvider);

    return Scaffold(
      appBar: SectionAppBar(
        title: l10n.tabDebts,
        actions: [
          IconButton(
            tooltip: l10n.bulkSmsTitle,
            icon: const Icon(Icons.campaign_rounded),
            onPressed: () => context.push(Routes.bulkSms),
          ),
        ],
      ),
      floatingActionButton: liftAboveNav(context, FloatingActionButton(
        // Вкладки живут в одном дереве: одинаковые Hero-теги кнопок вызывают ошибку при переходах.
        heroTag: null,
        tooltip: l10n.addDebtor,
        onPressed: () {
          HapticFeedback.selectionClick();
          context.push(Routes.debtorNew);
        },
        child: const Icon(Icons.person_add_alt_1_rounded),
      )),
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

/// Экран с данными: обзор → поиск с фильтром (закреплён) → список.
class _DebtorList extends ConsumerStatefulWidget {
  const _DebtorList({required this.all});

  final List<DebtorSummary> all;

  @override
  ConsumerState<_DebtorList> createState() => _DebtorListState();
}

class _DebtorListState extends ConsumerState<_DebtorList> {
  /// Появление карточек играет только при открытии экрана. Позже, при прокрутке,
  /// карточки создаются заново, и анимация оставляла бы на их месте пустоту.
  bool _intro = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _intro = false);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.all;
    final l10n = context.l10n;
    final filter = ref.watch(selectedDebtFilterProvider);
    final config = ref.watch(debtFilterConfigProvider);
    final rows = ref.watch(visibleDebtorsProvider) ?? const <DebtorRow>[];
    final now = DateTime.now();
    final overview = computeOverview(all, now: now, config: config);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        // 1. Общий долг — самый верх.
        SliverToBoxAdapter(child: DebtsOverviewCard(overview: overview, trend: ref.watch(debtTrendProvider))),

        // 2. Поиск с воронкой фильтров в конце поля; не уезжает при прокрутке.
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeader(
            height: 60,
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: DebouncedSearchField(
                compact: true,
                hintText: l10n.searchHint,
                clearTooltip: l10n.searchClear,
                initialText: ref.read(debtSearchQueryProvider),
                onChanged: ref.read(debtSearchQueryProvider.notifier).set,
                trailingActions: const [DebtFilterButton()],
              ),
            ),
          ),
        ),

        // Включённый фильтр виден и снимается одним нажатием.
        if (filter != DebtFilter.all)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: Icon(debtFilterIcon(filter), size: 18),
                  label: Text('${debtFilterLabel(l10n, filter)} · ${rows.length}'),
                  deleteButtonTooltipMessage: l10n.filterReset,
                  onDeleted: () => ref.read(selectedDebtFilterProvider.notifier).select(DebtFilter.all),
                ),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: LoginPromptCard()),

        // 3. Список.
        if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  ref.watch(debtSearchQueryProvider).trim().isEmpty
                      ? l10n.debtsFilteredEmpty
                      : l10n.searchNoResults,
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
            padding: EdgeInsets.fromLTRB(16, 4, 16, 96 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                return FadeSlideIn(
                  key: ValueKey(row.summary.debtor.id),
                  enabled: _intro,
                  delay: Duration(milliseconds: i < 8 ? i * 35 : 0),
                  child: DebtorTile(
                    summary: row.summary,
                    now: now,
                    overdue: isOverdue(row.summary, now, config),
                    matchedPhone: row.matchedPhone,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Закреплённая под обзором строка (поиск + фильтр). Пока под ней ничего нет — прозрачная;
/// когда карточки заходят под неё, становится матовым стеклом: размытие и лёгкая подложка
/// цвета фона, без тёмной плашки и смены цвета шапки.
class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader({required this.height, required this.child, required this.color});

  final double height;
  final Widget child;
  final Color color;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: overlapsContent ? 16 : 0.001,
          sigmaY: overlapsContent ? 16 : 0.001,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color: color.withValues(alpha: overlapsContent ? 0.62 : 0),
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeader old) => true;
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
        const LoginPromptCard(),
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
