import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../domain/product_summary.dart';
import 'product_image.dart';
import 'product_labels.dart';

/// Карточка товара в сетке каталога.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.summary});

  final ProductSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final p = summary.product;
    final pack = packLineText(l10n, p);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.productDetails(p.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'product-${p.id}',
                    child: ProductImage(fileName: summary.coverFileName, cacheWidth: 480),
                  ),
                  if (!p.inStock)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text(
                            l10n.outOfStock,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    unitPriceText(l10n, p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (pack != null)
                    Text(
                      pack,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
