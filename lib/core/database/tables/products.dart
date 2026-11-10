import 'package:drift/drift.dart';

import '../../domain/product_unit.dart';
import '../sync_columns.dart';

/// Товар каталога оптовика. Цены — целые суммы (UZS).
///
/// Упаковка необязательна, но задаётся целиком: [packKind], [packSize] и
/// [packPrice] либо все пустые, либо все заполнены.
class Products extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().nullable()();
  TextColumn get category => text().nullable()();
  IntColumn get unit => intEnum<ProductUnit>()();

  /// Цена за одну единицу.
  IntColumn get unitPrice => integer()();

  IntColumn get packKind => intEnum<PackKind>().nullable()();

  /// Сколько единиц в упаковке.
  IntColumn get packSize => integer().nullable()();

  /// Цена за упаковку целиком (обычно ниже, чем packSize × unitPrice).
  IntColumn get packPrice => integer().nullable()();

  /// Минимальная партия в единицах.
  IntColumn get minOrderQuantity => integer().withDefault(const Constant(1))();

  BoolColumn get inStock => boolean().withDefault(const Constant(true))();
}

/// Фото товара. Хранится имя файла в папке приложения (не полный путь: он
/// может меняться между запусками). [position] 0 — обложка.
@TableIndex(name: 'idx_product_photos_product', columns: {#productId})
class ProductPhotos extends Table with SyncColumns {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get fileName => text()();
  IntColumn get position => integer()();
}
