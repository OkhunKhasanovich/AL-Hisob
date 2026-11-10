import '../../../core/database/app_database.dart';

/// Товар вместе с фото (обложка — первое).
class ProductSummary {
  const ProductSummary({required this.product, required this.photos});

  final Product product;
  final List<ProductPhoto> photos;

  String? get coverFileName => photos.isEmpty ? null : photos.first.fileName;
}

/// Собирает сводки; удалённые записи игнорируются, фото упорядочены по позиции.
List<ProductSummary> buildProductSummaries({
  required Iterable<Product> products,
  required Iterable<ProductPhoto> photos,
}) {
  final byProduct = <String, List<ProductPhoto>>{};
  for (final p in photos) {
    if (p.deletedAt == null) (byProduct[p.productId] ??= []).add(p);
  }
  for (final list in byProduct.values) {
    list.sort((a, b) => a.position.compareTo(b.position));
  }
  return [
    for (final product in products)
      if (product.deletedAt == null)
        ProductSummary(product: product, photos: byProduct[product.id] ?? const []),
  ];
}
