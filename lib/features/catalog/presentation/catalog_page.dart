import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/shop_role.dart';
import '../../../core/widgets/section_app_bar.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/debounced_search_field.dart';
import '../../../core/widgets/feature_placeholder.dart';
import '../../../core/widgets/skeleton.dart';
import '../../profile/profile_providers.dart';
import '../data/catalog_providers.dart';
import 'product_card.dart';
import '../../shell/floating_nav_bar.dart';

/// Вкладка «Каталог». Оптовик ведёт свой каталог; для покупателя здесь
/// появятся каталоги оптовиков после синхронизации (этапы 8–9).
class CatalogPage extends ConsumerWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(shopProfileProvider);

    return profile.when(
      loading: () => Scaffold(
        appBar: SectionAppBar(title: l10n.tabCatalog),
        body: const Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
      ),
      error: (e, _) => Scaffold(appBar: SectionAppBar(title: l10n.tabCatalog), body: Center(child: Text('$e'))),
      data: (p) => (p?.roles.contains(ShopRole.wholesaler) ?? false)
          ? const _WholesalerCatalog()
          : FeaturePlaceholder(
              title: l10n.tabCatalog,
              message: l10n.catalogBuyerPlaceholder,
              icon: Icons.inventory_2_rounded,
            ),
    );
  }
}

class _WholesalerCatalog extends ConsumerWidget {
  const _WholesalerCatalog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final summaries = ref.watch(productSummariesProvider);

    return Scaffold(
      appBar: SectionAppBar(title: l10n.tabCatalog),
      floatingActionButton: liftAboveNav(context, FloatingActionButton.extended(
        // Вкладки живут в одном дереве: одинаковые Hero-теги кнопок вызывают ошибку при переходах.
        heroTag: null,
        onPressed: () {
          HapticFeedback.selectionClick();
          context.push(Routes.productNew);
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.addProduct),
      )),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(productSummariesProvider),
        child: summaries.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [SkeletonList(itemCount: 4, itemHeight: 120)],
          ),
          error: (e, _) => ListView(padding: const EdgeInsets.all(32), children: [Text('$e')]),
          data: (all) => all.isEmpty ? const _EmptyCatalog() : const _ProductGrid(),
        ),
      ),
    );
  }
}

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final visible = ref.watch(visibleProductsProvider) ?? const [];
    final categories = ref.watch(catalogCategoriesProvider);
    final selected = ref.watch(catalogCategoryProvider);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DebouncedSearchField(
              hintText: l10n.catalogSearchHint,
              clearTooltip: l10n.searchClear,
              initialText: ref.read(catalogQueryProvider),
              onChanged: ref.read(catalogQueryProvider.notifier).set,
            ),
          ),
        ),
        if (categories.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(l10n.filterAll),
                      selected: selected == null,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        ref.read(catalogCategoryProvider.notifier).select(null);
                      },
                    ),
                  ),
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: selected == c,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          ref.read(catalogCategoryProvider.notifier).select(c);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.searchNoResults, textAlign: TextAlign.center),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.66,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) => ProductCard(
                key: ValueKey(visible[i].product.id),
                summary: visible[i],
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.inventory_2_rounded, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(l10n.catalogEmptyTitle, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          l10n.catalogEmptyHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
