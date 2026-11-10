import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/settings/settings_providers.dart';
import '../domain/photo_services.dart';
import '../domain/product_search.dart';
import '../domain/product_summary.dart';
import 'image_picker_photo_picker.dart';
import 'local_photo_storage.dart';
import 'products_repository.dart';

final productsRepositoryProvider = Provider<ProductsRepository>(
  (ref) => ProductsRepository(ref.watch(appDatabaseProvider)),
);

/// Все товары с фото; обновляется при любых изменениях в БД.
final productSummariesProvider = StreamProvider<List<ProductSummary>>(
  (ref) => ref.watch(productsRepositoryProvider).watchSummaries(),
);

final productDetailsProvider = StreamProvider.autoDispose.family<ProductSummary?, String>(
  (ref, id) => ref.watch(productsRepositoryProvider).watchProduct(id),
);

/// Папка с фото товаров. Переопределяется в тестах.
final photoDirectoryProvider = FutureProvider<Directory>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/product_photos');
});

final photoStorageProvider = FutureProvider<PhotoStorage>((ref) async {
  return LocalPhotoStorage(await ref.watch(photoDirectoryProvider.future));
});

/// Переопределяется в тестах.
final photoPickerProvider = Provider<PhotoPicker>((ref) => ImagePickerPhotoPicker());

// ---------- поиск и фильтр списка ----------

class CatalogQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final catalogQueryProvider = NotifierProvider<CatalogQuery, String>(CatalogQuery.new);

/// Выбранная категория; `null` — все.
class CatalogCategory extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? category) => state = category;
}

final catalogCategoryProvider = NotifierProvider<CatalogCategory, String?>(CatalogCategory.new);

final productSearchIndexProvider = Provider<ProductSearchIndex?>((ref) {
  final all = ref.watch(productSummariesProvider).value;
  return all == null ? null : ProductSearchIndex(all);
});

/// Категории, которые есть у товаров (по алфавиту).
final catalogCategoriesProvider = Provider<List<String>>((ref) {
  final all = ref.watch(productSummariesProvider).value ?? const <ProductSummary>[];
  final set = {
    for (final s in all)
      if (s.product.category != null) s.product.category!,
  }.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return set;
});

/// Товары к показу: поиск (по релевантности) и фильтр категории.
final visibleProductsProvider = Provider<List<ProductSummary>?>((ref) {
  final index = ref.watch(productSearchIndexProvider);
  if (index == null) return null;
  final query = ref.watch(catalogQueryProvider);
  final category = ref.watch(catalogCategoryProvider);
  final hits = index.search(query);
  return [
    for (final h in hits)
      if (category == null || h.summary.product.category == category) h.summary,
  ];
});
