import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../data/catalog_providers.dart';
import '../domain/product_pricing.dart';
import '../domain/product_summary.dart';
import 'photo_viewer.dart';
import 'product_image.dart';
import 'product_labels.dart';

class ProductDetailsPage extends ConsumerWidget {
  const ProductDetailsPage({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(productDetailsProvider(productId));
    return details.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      // null — товар удалён: экран уже закрывается.
      data: (s) => s == null ? Scaffold(appBar: AppBar()) : _Content(summary: s),
    );
  }
}

class _Content extends ConsumerStatefulWidget {
  const _Content({required this.summary});

  final ProductSummary summary;

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final l10n = context.l10n;
    final repo = ref.read(productsRepositoryProvider);
    final storage = await ref.read(photoStorageProvider.future);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteProductTitle),
        content: Text(l10n.deleteProductBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.deleteButton)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = widget.summary.product.id;
    context.pop(); // сначала закрываем экран, потом удаляем
    final files = await repo.deleteProduct(id);
    for (final f in files) {
      await storage.delete(f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = widget.summary;
    final p = summary.product;
    final photos = summary.photos;
    final pack = hasPack(p);
    final discount = packDiscountPercent(p);
    final perUnit = packUnitPrice(p);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l10n.editButton,
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push(Routes.productEdit(p.id)),
          ),
          IconButton(
            tooltip: l10n.deleteButton,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('product-details-list'),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AspectRatio(
            aspectRatio: 1.2,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: photos.isEmpty ? 1 : photos.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final image = ProductImage(
                      fileName: photos.isEmpty ? null : photos[i].fileName,
                      iconSize: 72,
                    );
                    return GestureDetector(
                      onTap: photos.isEmpty
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => PhotoViewerPage(summary: summary, initialIndex: i),
                              )),
                      child: SizedBox.expand(
                        child: i == 0 ? Hero(tag: 'product-${p.id}', child: image) : image,
                      ),
                    );
                  },
                ),
                if (photos.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < photos.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page ? scheme.primary : scheme.surface.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: theme.textTheme.headlineSmall),
                if (p.category != null) ...[
                  const SizedBox(height: 8),
                  Chip(label: Text(p.category!), visualDensity: VisualDensity.compact),
                ],
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.productUnitPriceLabel, style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(
                          unitPriceText(l10n, p),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (pack) ...[
                          const Divider(height: 24),
                          Text(
                            '${packLabel(l10n, p.packKind!)} · ${p.packSize} ${unitLabel(l10n, p.unit)}',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatAmount(p.packPrice!)} ${l10n.currencySum}',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (perUnit != null)
                            Text(
                              l10n.packPerUnitHint('${formatAmount(perUnit.round())} ${l10n.currencySum}'),
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          if (discount != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                l10n.packDiscount(discount),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                        const Divider(height: 24),
                        Row(children: [
                          Icon(Icons.shopping_basket_rounded, size: 20, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(l10n.minOrderValue(formatAmount(p.minOrderQuantity), unitLabel(l10n, p.unit))),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.inStockLabel),
                  value: p.inStock,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    ref.read(productsRepositoryProvider).setInStock(p.id, v);
                  },
                ),
                if (p.description != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(p.description!, style: theme.textTheme.bodyLarge),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
