import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/database/sync_columns.dart';
import 'package:al_savdogar/core/domain/product_unit.dart';
import 'package:al_savdogar/features/catalog/domain/product_pricing.dart';
import 'package:al_savdogar/features/catalog/domain/product_search.dart';
import 'package:al_savdogar/features/catalog/domain/product_summary.dart';

final _t = DateTime(2026, 1, 1);

Product product(
  String name, {
  String? category,
  int unitPrice = 1000,
  PackKind? packKind,
  int? packSize,
  int? packPrice,
  int minOrder = 1,
  DateTime? deletedAt,
}) =>
    Product(
      id: name,
      createdAt: _t,
      updatedAt: _t,
      deletedAt: deletedAt,
      syncStatus: SyncStatus.pending,
      name: name,
      category: category,
      unit: ProductUnit.piece,
      unitPrice: unitPrice,
      packKind: packKind,
      packSize: packSize,
      packPrice: packPrice,
      minOrderQuantity: minOrder,
      inStock: true,
    );

ProductPhoto photo(String productId, String file, int position, {DateTime? deletedAt}) => ProductPhoto(
      id: '$productId-$file',
      createdAt: _t,
      updatedAt: _t,
      deletedAt: deletedAt,
      syncStatus: SyncStatus.pending,
      productId: productId,
      fileName: file,
      position: position,
    );

ProductSummary summary(Product p) => ProductSummary(product: p, photos: const []);

void main() {
  group('цены и упаковка', () {
    final box = product('Cola', unitPrice: 12000, packKind: PackKind.box, packSize: 24, packPrice: 250000);

    test('упаковка задана только целиком', () {
      expect(hasPack(box), isTrue);
      expect(hasPack(product('X')), isFalse);
      expect(hasPack(product('X', packKind: PackKind.box)), isFalse);
      expect(hasPack(product('X', packKind: PackKind.box, packSize: 10)), isFalse);
    });

    test('цена за единицу в упаковке', () {
      expect(packUnitPrice(box), closeTo(10416.67, 0.01));
      expect(packUnitPrice(product('X')), isNull);
    });

    test('скидка за упаковку', () {
      // 24 × 12 000 = 288 000, упаковка 250 000 → 13,2 % → 13
      expect(packDiscountPercent(box), 13);
      expect(packDiscountPercent(product('X')), isNull);
    });

    test('нет скидки, если упаковка не дешевле', () {
      final same = product('X', unitPrice: 100, packKind: PackKind.box, packSize: 10, packPrice: 1000);
      final pricier = product('X', unitPrice: 100, packKind: PackKind.box, packSize: 10, packPrice: 1200);
      expect(packDiscountPercent(same), isNull);
      expect(packDiscountPercent(pricier), isNull);
    });

    test('orderTotal без упаковки', () {
      final p = product('X', unitPrice: 500);
      expect(orderTotal(p, 0), 0);
      expect(orderTotal(p, -3), 0);
      expect(orderTotal(p, 7), 3500);
    });

    test('orderTotal: целые упаковки по цене упаковки, остаток поштучно', () {
      expect(orderTotal(box, 24), 250000);
      expect(orderTotal(box, 48), 500000);
      expect(orderTotal(box, 30), 250000 + 6 * 12000);
      expect(orderTotal(box, 5), 5 * 12000);
      expect(orderTotal(box, 100), 4 * 250000 + 4 * 12000);
    });

    test('минимальная партия', () {
      final p = product('X', minOrder: 10);
      expect(meetsMinOrder(p, 9), isFalse);
      expect(meetsMinOrder(p, 10), isTrue);
      expect(meetsMinOrder(p, 50), isTrue);
    });
  });

  group('buildProductSummaries', () {
    test('фото по порядку позиций, удалённые пропускаются', () {
      final list = buildProductSummaries(
        products: [product('A'), product('B', deletedAt: _t)],
        photos: [
          photo('A', 'c.jpg', 2),
          photo('A', 'a.jpg', 0),
          photo('A', 'b.jpg', 1, deletedAt: _t),
          photo('B', 'z.jpg', 0),
        ],
      );
      expect(list, hasLength(1));
      expect(list.single.photos.map((p) => p.fileName), ['a.jpg', 'c.jpg']);
      expect(list.single.coverFileName, 'a.jpg');
    });

    test('без фото нет обложки', () {
      final list = buildProductSummaries(products: [product('A')], photos: const []);
      expect(list.single.coverFileName, isNull);
    });
  });

  group('поиск по каталогу', () {
    final items = [
      summary(product('Coca-Cola 1.5L', category: 'Напитки')),
      summary(product('Pepsi 1L', category: 'Напитки')),
      summary(product('Гречка', category: 'Крупы')),
      summary(product('Рис Lazer', category: 'Крупы')),
      summary(product('Sut Nestle', category: 'Sut mahsulotlari')),
      summary(product('Шоколад Alpen Gold')),
    ];
    final index = ProductSearchIndex(items);
    List<String> found(String q) => index.search(q).map((h) => h.summary.product.name).toList();

    test('транслитерация: латиница находит кириллицу и наоборот', () {
      expect(found('Grechka'), ['Гречка']);
      expect(found('Гречка'), ['Гречка']);
      expect(found('Shokolad'), ['Шоколад Alpen Gold']);
      expect(found('Кока кола'), ['Coca-Cola 1.5L']);
      expect(found('Ris'), ['Рис Lazer']);
    });

    test('опечатки', () {
      expect(found('Pepsy'), ['Pepsi 1L']);
      expect(found('Grehcka'), ['Гречка']);
      expect(found('Alpne'), ['Шоколад Alpen Gold']);
    });

    test('по мере набора', () {
      expect(found('Gre'), ['Гречка']);
      expect(found('Nes'), ['Sut Nestle']);
    });

    test('по категории', () {
      expect(found('Напитки'), unorderedEquals(['Coca-Cola 1.5L', 'Pepsi 1L']));
      expect(found('Napitki'), unorderedEquals(['Coca-Cola 1.5L', 'Pepsi 1L']));
      expect(found('Krupy'), unorderedEquals(['Гречка', 'Рис Lazer']));
    });

    test('название весомее категории', () {
      final idx = ProductSearchIndex([
        summary(product('Чай чёрный', category: 'Кофе')),
        summary(product('Кофе растворимый', category: 'Напитки')),
      ]);
      expect(idx.search('кофе').map((h) => h.summary.product.name),
          ['Кофе растворимый', 'Чай чёрный']);
    });

    test('все слова запроса обязаны найтись', () {
      expect(found('Pepsi Nestle'), isEmpty);
      expect(found('Alpen Gold'), ['Шоколад Alpen Gold']);
    });

    test('нет совпадений', () => expect(found('Davron'), isEmpty));

    test('пустой запрос — все в исходном порядке', () {
      expect(found('  '), items.map((i) => i.product.name).toList());
    });

    test('точное название выше частичного', () {
      final idx = ProductSearchIndex([
        summary(product('Pepsi 1L Max')),
        summary(product('Pepsi')),
      ]);
      expect(idx.search('Pepsi').first.summary.product.name, 'Pepsi');
    });
  });
}
