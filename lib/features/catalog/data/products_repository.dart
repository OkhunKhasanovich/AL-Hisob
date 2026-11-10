import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_columns.dart';
import '../../../core/database/watch.dart';
import '../../../core/domain/product_unit.dart';
import '../../../core/utils/money.dart';
import '../domain/product_summary.dart';

/// Максимум фото у одного товара.
const maxProductPhotos = 5;
const maxMinOrderQuantity = 9999999;

class PackInput {
  const PackInput({required this.kind, required this.size, required this.price});

  final PackKind kind;

  /// Единиц в упаковке (от 2).
  final int size;

  /// Цена за упаковку.
  final int price;
}

class ProductInput {
  const ProductInput({
    required this.name,
    required this.unit,
    required this.unitPrice,
    this.description,
    this.category,
    this.pack,
    this.minOrderQuantity = 1,
    this.inStock = true,
  });

  final String name;
  final String? description;
  final String? category;
  final ProductUnit unit;
  final int unitPrice;
  final PackInput? pack;
  final int minOrderQuantity;
  final bool inStock;
}

class ProductsRepository {
  ProductsRepository(this._db);

  final AppDatabase _db;

  // ---------- чтение ----------

  Future<List<ProductSummary>> loadSummaries() async {
    final products = await (_db.select(_db.products)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    final photos =
        await (_db.select(_db.productPhotos)..where((t) => t.deletedAt.isNull())).get();
    return buildProductSummaries(products: products, photos: photos);
  }

  Stream<List<ProductSummary>> watchSummaries() =>
      watchTables(_db, [_db.products, _db.productPhotos], loadSummaries);

  Future<ProductSummary?> loadProduct(String id) async {
    final product = await (_db.select(_db.products)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (product == null) return null;
    final photos = await (_db.select(_db.productPhotos)
          ..where((t) => t.productId.equals(id) & t.deletedAt.isNull()))
        .get();
    return buildProductSummaries(products: [product], photos: photos).single;
  }

  Stream<ProductSummary?> watchProduct(String id) =>
      watchTables(_db, [_db.products, _db.productPhotos], () => loadProduct(id));

  /// Использованные категории по алфавиту.
  Future<List<String>> categories() async {
    final rows = await (_db.selectOnly(_db.products, distinct: true)
          ..addColumns([_db.products.category])
          ..where(_db.products.deletedAt.isNull() & _db.products.category.isNotNull()))
        .get();
    final list = [for (final r in rows) r.read(_db.products.category)!];
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  // ---------- товары ----------

  /// Создаёт товар; [photoFiles] — уже сохранённые в папке приложения файлы (первый — обложка).
  Future<String> createProduct(ProductInput input, {List<String> photoFiles = const []}) {
    final c = _validate(input);
    if (photoFiles.length > maxProductPhotos) {
      throw ArgumentError.value(photoFiles.length, 'photoFiles', 'At most $maxProductPhotos photos');
    }
    return _db.transaction(() async {
      final product = await _db.into(_db.products).insertReturning(_companion(c));
      for (var i = 0; i < photoFiles.length; i++) {
        await _db.into(_db.productPhotos).insert(
              ProductPhotosCompanion.insert(
                productId: product.id,
                fileName: photoFiles[i],
                position: i,
              ),
            );
      }
      return product.id;
    });
  }

  Future<void> updateProduct(String id, ProductInput input) async {
    final c = _validate(input);
    await (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(
        name: Value(c.name),
        description: Value(c.description),
        category: Value(c.category),
        unit: Value(c.unit),
        unitPrice: Value(c.unitPrice),
        packKind: Value(c.pack?.kind),
        packSize: Value(c.pack?.size),
        packPrice: Value(c.pack?.price),
        minOrderQuantity: Value(c.minOrderQuantity),
        inStock: Value(c.inStock),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
  }

  Future<void> setInStock(String id, bool inStock) =>
      (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
        ProductsCompanion(
          inStock: Value(inStock),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

  /// Soft delete товара и его фото. Возвращает имена файлов, которые теперь
  /// можно удалить с диска.
  Future<List<String>> deleteProduct(String id) {
    return _db.transaction(() async {
      final now = DateTime.now();
      final photos = await (_db.select(_db.productPhotos)
            ..where((t) => t.productId.equals(id) & t.deletedAt.isNull()))
          .get();
      await (_db.update(_db.productPhotos)
            ..where((t) => t.productId.equals(id) & t.deletedAt.isNull()))
          .write(ProductPhotosCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ));
      await (_db.update(_db.products)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .write(ProductsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ));
      return [for (final p in photos) p.fileName];
    });
  }

  // ---------- фото ----------

  /// Добавляет фото в конец. Больше [maxProductPhotos] нельзя.
  Future<ProductPhoto> addPhoto(String productId, String fileName) {
    return _db.transaction(() async {
      final existing = await _activePhotos(productId);
      if (existing.length >= maxProductPhotos) {
        throw StateError('A product can have at most $maxProductPhotos photos');
      }
      return _db.into(_db.productPhotos).insertReturning(
            ProductPhotosCompanion.insert(
              productId: productId,
              fileName: fileName,
              position: existing.isEmpty ? 0 : existing.last.position + 1,
            ),
          );
    });
  }

  /// Soft delete фото; остальные сдвигаются так, чтобы позиции шли подряд.
  /// Возвращает имя файла для удаления с диска (или `null`, если фото нет).
  Future<String?> removePhoto(String photoId) {
    return _db.transaction(() async {
      final photo = await (_db.select(_db.productPhotos)
            ..where((t) => t.id.equals(photoId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (photo == null) return null;
      final now = DateTime.now();
      await (_db.update(_db.productPhotos)..where((t) => t.id.equals(photoId))).write(
        ProductPhotosCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _renumber(photo.productId);
      return photo.fileName;
    });
  }

  /// Делает фото обложкой (позиция 0), остальные сохраняют порядок.
  Future<void> setCover(String photoId) {
    return _db.transaction(() async {
      final photo = await (_db.select(_db.productPhotos)
            ..where((t) => t.id.equals(photoId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (photo == null) return;
      final all = await _activePhotos(photo.productId);
      final ordered = [photo, ...all.where((p) => p.id != photoId)];
      await _applyOrder(ordered);
    });
  }

  Future<List<ProductPhoto>> _activePhotos(String productId) =>
      (_db.select(_db.productPhotos)
            ..where((t) => t.productId.equals(productId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();

  Future<void> _renumber(String productId) async => _applyOrder(await _activePhotos(productId));

  Future<void> _applyOrder(List<ProductPhoto> ordered) async {
    final now = DateTime.now();
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].position == i) continue;
      await (_db.update(_db.productPhotos)..where((t) => t.id.equals(ordered[i].id))).write(
        ProductPhotosCompanion(
          position: Value(i),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
    }
  }

  // ---------- проверка и очистка ввода ----------

  ProductsCompanion _companion(ProductInput c) => ProductsCompanion.insert(
        name: c.name,
        unit: c.unit,
        unitPrice: c.unitPrice,
        description: Value(c.description),
        category: Value(c.category),
        packKind: Value(c.pack?.kind),
        packSize: Value(c.pack?.size),
        packPrice: Value(c.pack?.price),
        minOrderQuantity: Value(c.minOrderQuantity),
        inStock: Value(c.inStock),
      );

  ProductInput _validate(ProductInput input) {
    final name = input.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.length > 120) {
      throw ArgumentError.value(input.name, 'name', 'Name must be 1..120 characters');
    }
    if (input.unitPrice <= 0 || input.unitPrice > maxAmount) {
      throw ArgumentError.value(input.unitPrice, 'unitPrice', 'Price must be in 1..$maxAmount');
    }
    final pack = input.pack;
    if (pack != null) {
      if (pack.size < 2 || pack.size > 1000000) {
        throw ArgumentError.value(pack.size, 'pack.size', 'Pack size must be 2..1000000');
      }
      if (pack.price <= 0 || pack.price > maxAmount) {
        throw ArgumentError.value(pack.price, 'pack.price', 'Price must be in 1..$maxAmount');
      }
    }
    if (input.minOrderQuantity < 1 || input.minOrderQuantity > maxMinOrderQuantity) {
      throw ArgumentError.value(
          input.minOrderQuantity, 'minOrderQuantity', 'Must be in 1..$maxMinOrderQuantity');
    }
    final category = _blankToNull(input.category);
    if (category != null && category.length > 60) {
      throw ArgumentError.value(input.category, 'category', 'At most 60 characters');
    }
    final description = _blankToNull(input.description);
    if (description != null && description.length > 2000) {
      throw ArgumentError.value(input.description, 'description', 'At most 2000 characters');
    }
    return ProductInput(
      name: name,
      description: description,
      category: category?.replaceAll(RegExp(r'\s+'), ' '),
      unit: input.unit,
      unitPrice: input.unitPrice,
      pack: pack,
      minOrderQuantity: input.minOrderQuantity,
      inStock: input.inStock,
    );
  }
}

String? _blankToNull(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
