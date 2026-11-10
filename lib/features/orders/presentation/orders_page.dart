import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/shop_role.dart';
import '../../../core/widgets/section_app_bar.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/feature_placeholder.dart';
import '../../../core/widgets/skeleton.dart';
import '../../profile/profile_providers.dart';
import '../data/orders_providers.dart';
import '../domain/order_models.dart';
import '../domain/order_workflow.dart';
import 'order_labels.dart';
import '../../shell/glass_nav_bar.dart';

/// Вкладка «Заказы». Оптовик ведёт заказы покупателей; у покупателя они
/// появятся после синхронизации (этапы 8–9).
class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(shopProfileProvider);

    return profile.when(
      loading: () => Scaffold(
        appBar: SectionAppBar(title: l10n.tabOrders),
        body: const Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
      ),
      error: (e, _) =>
          Scaffold(appBar: SectionAppBar(title: l10n.tabOrders), body: Center(child: Text('$e'))),
      data: (p) => (p?.roles.contains(ShopRole.wholesaler) ?? false)
          ? const _WholesalerOrders()
          : FeaturePlaceholder(
              title: l10n.tabOrders,
              message: l10n.ordersBuyerPlaceholder,
              icon: Icons.local_shipping_rounded,
            ),
    );
  }
}

class _WholesalerOrders extends ConsumerWidget {
  const _WholesalerOrders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final all = ref.watch(orderSummariesProvider);

    return Scaffold(
      appBar: SectionAppBar(title: l10n.tabOrders),
      floatingActionButton: liftAboveNav(context, FloatingActionButton.extended(
        // Вкладки живут в одном дереве: одинаковые Hero-теги кнопок вызывают ошибку при переходах.
        heroTag: null,
        onPressed: () {
          HapticFeedback.selectionClick();
          context.push(Routes.orderNew);
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.newOrder),
      )),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(orderSummariesProvider),
        child: all.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [SkeletonList(itemCount: 5)],
          ),
          error: (e, _) => ListView(padding: const EdgeInsets.all(32), children: [Text('$e')]),
          data: (orders) => orders.isEmpty ? const _EmptyOrders() : const _OrderList(),
        ),
      ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  const _OrderList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final visible = ref.watch(visibleOrdersProvider) ?? const <OrderSummary>[];
    final selected = ref.watch(selectedOrderGroupProvider);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final g in OrderGroup.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(groupLabel(l10n, g)),
                      selected: selected == g,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        ref.read(selectedOrderGroupProvider.notifier).select(g);
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
                child: Text(l10n.debtsFilteredEmpty, textAlign: TextAlign.center),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 96 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) => _OrderTile(summary: visible[i]),
            ),
          ),
      ],
    );
  }
}

String _dateOf(DateTime t) => formatDate(t);

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.summary});

  final OrderSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final o = summary.order;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.orderDetails(o.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.orderNumberTitle(o.number),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  StatusChip(status: o.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                summary.customerName,
                style: theme.textTheme.bodyLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_dateOf(o.createdAt)} · ${l10n.orderItemsCount(summary.itemCount)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    '${formatAmount(o.total)} ${l10n.currencySum}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.local_shipping_rounded, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(l10n.ordersEmptyTitle, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          l10n.ordersEmptyHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
