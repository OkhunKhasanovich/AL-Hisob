import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../catalog/data/catalog_providers.dart';
import '../../catalog/domain/product_search.dart';
import '../../catalog/domain/product_summary.dart';
import '../../catalog/presentation/product_image.dart';
import '../../catalog/presentation/product_labels.dart';

/// Шторка выбора товаров для заказа. Только товары «в наличии»;
/// уже добавленные ([alreadyAdded] — id товаров) отмечены и недоступны.
Future<List<ProductSummary>?> showProductPicker(
  BuildContext context, {
  required Set<String> alreadyAdded,
}) {
  return showModalBottomSheet<List<ProductSummary>>(
    // Поверх стеклянной панели вкладок, а не под ней.
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _ProductPicker(alreadyAdded: alreadyAdded, scrollController: controller),
    ),
  );
}

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.alreadyAdded, required this.scrollController});

  final Set<String> alreadyAdded;
  final ScrollController scrollController;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  String _query = '';
  final Map<String, ProductSummary> _selected = {};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = ref.watch(productSummariesProvider).value ?? const <ProductSummary>[];
    final inStock = [for (final s in all) if (s.product.inStock) s];
    final hits = ProductSearchIndex(inStock).search(_query);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: l10n.catalogSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
        ),
        Expanded(
          child: inStock.isEmpty
              ? Center(child: Text(l10n.orderPickerEmpty))
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: hits.length,
                  itemBuilder: (context, i) {
                    final s = hits[i].summary;
                    final p = s.product;
                    final added = widget.alreadyAdded.contains(p.id);
                    return CheckboxListTile(
                      value: added || _selected.containsKey(p.id),
                      onChanged: added
                          ? null
                          : (v) => setState(() {
                                if (v ?? false) {
                                  _selected[p.id] = s;
                                } else {
                                  _selected.remove(p.id);
                                }
                              }),
                      secondary: SizedBox(
                        width: 48,
                        height: 48,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ProductImage(fileName: s.coverFileName, cacheWidth: 120, iconSize: 24),
                        ),
                      ),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(unitPriceText(l10n, p)),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selected.values.toList()),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(l10n.orderPickerAdd(_selected.length)),
            ),
          ),
        ),
      ],
    );
  }
}
