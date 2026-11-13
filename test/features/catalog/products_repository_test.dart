import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/database/sync_columns.dart';
import 'package:al_hisob/core/domain/product_unit.dart';
import 'package:al_hisob/features/catalog/data/products_repository.dart';

void main() {
  late AppDatabase db;
  late ProductsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ProductsRepository(db);
  });
  tearDown(() => db.close());

  ProductInput input({
    String name = 'Coca-Cola 1.5L',
    int unitPrice = 12000,
    PackInput? pack,
    String? category,
    String? description,
    int minOrder = 1,
    bool inStock = true,
  }) =>
      ProductInput(
        name: name,
        unit: ProductUnit.piece,
        unitPrice: unitPrice,
        pack: pack,
        category: category,
        description: description,
        minOrderQuantity: minOrder,
        inStock: inStock,
      );

  group('создание и чтение', () {
    test('заполняет служебные поля и нормализует ввод', () async {
      final id = await repo.createProduct(input(
        name: '  Coca-Cola   1.5L ',
        category: '  Напитки  ',
        description: '   ',
      ));

      final p = (await repo.loadProduct(id))!.product;
      expect(p.id, hasLength(36));
      expect(p.name, 'Coca-Cola 1.5L');
      expect(p.category, 'Напитки');
      expect(p.description, isNull);
      expect(p.syncStatus, SyncStatus.pending);
      expect(p.deletedAt, isNull);
      expect(p.inStock, isTrue);
      expect(p.minOrderQuantity, 1);
    });

    test('упаковка и минимальная партия сохраняются', () async {
      final id = await repo.createProduct(input(
        pack: const PackInput(kind: PackKind.box, size: 24, price: 250000),
        minOrder: 24,
        inStock: false,
      ));
      final p = (await repo.loadProduct(id))!.product;
      expect([p.packKind, p.packSize, p.packPrice], [PackKind.box, 24, 250000]);
      expect(p.minOrderQuantity, 24);
      expect(p.inStock, isFalse);
    });

    test('список отсортирован по названию', () async {
      for (final n in ['Pepsi', 'Cola', 'Fanta']) {
        await repo.createProduct(input(name: n));
      }
      expect((await repo.loadSummaries()).map((s) => s.product.name), ['Cola', 'Fanta', 'Pepsi']);
    });

    test('создание сразу с фото: порядок = обложка первая', () async {
      final id = await repo.createProduct(input(), photoFiles: ['a.jpg', 'b.jpg']);
      final s = (await repo.loadProduct(id))!;
      expect(s.photos.map((p) => p.fileName), ['a.jpg', 'b.jpg']);
      expect(s.photos.map((p) => p.position), [0, 1]);
      expect(s.coverFileName, 'a.jpg');
    });

    test('нет такого товара', () async {
      expect(await repo.loadProduct('nope'), isNull);
    });
  });

  group('валидация', () {
    test('название', () async {
      expect(() => repo.createProduct(input(name: '   ')), throwsArgumentError);
      expect(() => repo.createProduct(input(name: 'a' * 121)), throwsArgumentError);
    });

    test('цена за единицу', () async {
      for (final price in [0, -1, 1000000000000]) {
        expect(() => repo.createProduct(input(unitPrice: price)), throwsArgumentError, reason: '$price');
      }
    });

    test('упаковка: размер от 2, цена положительная', () async {
      for (final pack in [
        const PackInput(kind: PackKind.box, size: 1, price: 100),
        const PackInput(kind: PackKind.box, size: 0, price: 100),
        const PackInput(kind: PackKind.box, size: 10, price: 0),
      ]) {
        expect(() => repo.createProduct(input(pack: pack)), throwsArgumentError);
      }
    });

    test('минимальная партия, категория, описание, число фото', () async {
      expect(() => repo.createProduct(input(minOrder: 0)), throwsArgumentError);
      expect(() => repo.createProduct(input(category: 'a' * 61)), throwsArgumentError);
      expect(() => repo.createProduct(input(description: 'a' * 2001)), throwsArgumentError);
      expect(
        () => repo.createProduct(input(), photoFiles: List.generate(6, (i) => '$i.jpg')),
        throwsArgumentError,
      );
      expect(await repo.loadSummaries(), isEmpty, reason: 'ничего не записалось');
    });
  });

  group('редактирование', () {
    test('меняет поля, добавляет и убирает упаковку', () async {
      final id = await repo.createProduct(input(pack: const PackInput(kind: PackKind.box, size: 24, price: 250000)));
      final before = (await repo.loadProduct(id))!.product;
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await repo.updateProduct(id, input(name: 'Cola Zero', unitPrice: 13000, category: 'Напитки'));

      final p = (await repo.loadProduct(id))!.product;
      expect(p.name, 'Cola Zero');
      expect(p.unitPrice, 13000);
      expect(p.category, 'Напитки');
      expect([p.packKind, p.packSize, p.packPrice], [null, null, null], reason: 'упаковка снята');
      expect(p.updatedAt.isAfter(before.updatedAt), isTrue);
      expect(p.createdAt, before.createdAt);
      expect(p.syncStatus, SyncStatus.pending);
    });

    test('setInStock', () async {
      final id = await repo.createProduct(input());
      await repo.setInStock(id, false);
      expect((await repo.loadProduct(id))!.product.inStock, isFalse);
      await repo.setInStock(id, true);
      expect((await repo.loadProduct(id))!.product.inStock, isTrue);
    });

    test('невалидное редактирование не портит данные', () async {
      final id = await repo.createProduct(input());
      expect(() => repo.updateProduct(id, input(unitPrice: 0)), throwsArgumentError);
      expect((await repo.loadProduct(id))!.product.unitPrice, 12000);
    });
  });

  group('удаление', () {
    test('soft delete: товар и фото скрыты, строки остались, возвращены файлы', () async {
      final id = await repo.createProduct(input(), photoFiles: ['a.jpg', 'b.jpg']);
      final other = await repo.createProduct(input(name: 'Fanta'));

      final files = await repo.deleteProduct(id);

      expect(files, unorderedEquals(['a.jpg', 'b.jpg']));
      expect(await repo.loadProduct(id), isNull);
      expect((await repo.loadSummaries()).map((s) => s.product.id), [other]);
      expect(await db.select(db.products).get(), hasLength(2));
      expect((await db.select(db.productPhotos).get()).every((p) => p.deletedAt != null), isTrue);
    });
  });

  group('фото', () {
    test('добавление в конец, не больше пяти', () async {
      final id = await repo.createProduct(input());
      for (var i = 0; i < maxProductPhotos; i++) {
        await repo.addPhoto(id, '$i.jpg');
      }
      expect((await repo.loadProduct(id))!.photos.map((p) => p.position), [0, 1, 2, 3, 4]);
      expect(() => repo.addPhoto(id, 'extra.jpg'), throwsStateError);
      expect((await repo.loadProduct(id))!.photos, hasLength(5));
    });

    test('удаление: позиции пересчитываются, возвращается имя файла', () async {
      final id = await repo.createProduct(input(), photoFiles: ['a.jpg', 'b.jpg', 'c.jpg']);
      final photos = (await repo.loadProduct(id))!.photos;

      final file = await repo.removePhoto(photos[1].id);

      expect(file, 'b.jpg');
      final after = (await repo.loadProduct(id))!.photos;
      expect(after.map((p) => p.fileName), ['a.jpg', 'c.jpg']);
      expect(after.map((p) => p.position), [0, 1]);
      expect(await repo.removePhoto(photos[1].id), isNull, reason: 'повторно — ничего');
    });

    test('после удаления можно снова добавить до лимита', () async {
      final id = await repo.createProduct(input(),
          photoFiles: List.generate(5, (i) => '$i.jpg'));
      final first = (await repo.loadProduct(id))!.photos.first;
      await repo.removePhoto(first.id);
      await repo.addPhoto(id, 'new.jpg');
      final photos = (await repo.loadProduct(id))!.photos;
      expect(photos.map((p) => p.fileName).last, 'new.jpg');
      expect(photos.map((p) => p.position), [0, 1, 2, 3, 4]);
    });

    test('обложка: выбранное фото становится первым, остальные в прежнем порядке', () async {
      final id = await repo.createProduct(input(), photoFiles: ['a.jpg', 'b.jpg', 'c.jpg']);
      final photos = (await repo.loadProduct(id))!.photos;

      await repo.setCover(photos[2].id);

      expect((await repo.loadProduct(id))!.photos.map((p) => p.fileName), ['c.jpg', 'a.jpg', 'b.jpg']);
      expect((await repo.loadProduct(id))!.coverFileName, 'c.jpg');
    });

    test('обложка, которая уже первая, ничего не меняет', () async {
      final id = await repo.createProduct(input(), photoFiles: ['a.jpg', 'b.jpg']);
      final photos = (await repo.loadProduct(id))!.photos;
      await repo.setCover(photos[0].id);
      expect((await repo.loadProduct(id))!.photos.map((p) => p.fileName), ['a.jpg', 'b.jpg']);
    });
  });

  group('replacePhotos', () {
    test('добавляет новые, убирает лишние, порядок как в списке', () async {
      final id = await repo.createProduct(input(), photoFiles: ['a.jpg', 'b.jpg', 'c.jpg']);

      final removed = await repo.replacePhotos(id, ['c.jpg', 'new.jpg', 'a.jpg']);

      expect(removed, ['b.jpg']);
      final photos = (await repo.loadProduct(id))!.photos;
      expect(photos.map((p) => p.fileName), ['c.jpg', 'new.jpg', 'a.jpg']);
      expect(photos.map((p) => p.position), [0, 1, 2]);
      expect((await db.select(db.productPhotos).get()).where((p) => p.deletedAt != null), hasLength(1));
    });

    test('пустой список снимает все фото', () async {
      final id = await repo.createProduct(input(), photoFiles: ['a.jpg', 'b.jpg']);
      expect(await repo.replacePhotos(id, const []), unorderedEquals(['a.jpg', 'b.jpg']));
      expect((await repo.loadProduct(id))!.photos, isEmpty);
    });

    test('без изменений — ничего не пишет', () async {
      final id = await repo.createProduct(input(), photoFiles: ['a.jpg', 'b.jpg']);
      final before = (await db.select(db.productPhotos).get()).map((p) => p.updatedAt).toList();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(await repo.replacePhotos(id, ['a.jpg', 'b.jpg']), isEmpty);

      final after = (await db.select(db.productPhotos).get()).map((p) => p.updatedAt).toList();
      expect(after, before);
    });

    test('лимит и дубликаты отклоняются', () async {
      final id = await repo.createProduct(input());
      expect(() => repo.replacePhotos(id, List.generate(6, (i) => '$i.jpg')), throwsArgumentError);
      expect(() => repo.replacePhotos(id, ['a.jpg', 'a.jpg']), throwsArgumentError);
      expect((await repo.loadProduct(id))!.photos, isEmpty);
    });
  });

  group('категории', () {
    test('уникальные, по алфавиту, без удалённых и пустых', () async {
      await repo.createProduct(input(name: 'A', category: 'Напитки'));
      await repo.createProduct(input(name: 'B', category: 'Напитки'));
      await repo.createProduct(input(name: 'C', category: 'Крупы'));
      await repo.createProduct(input(name: 'D'));
      final gone = await repo.createProduct(input(name: 'E', category: 'Удалённая'));
      await repo.deleteProduct(gone);

      expect(await repo.categories(), ['Крупы', 'Напитки']);
    });
  });

  group('потоки', () {
    test('watchSummaries обновляется при создании и изменении', () async {
      final events = <List<String>>[];
      final sub = repo.watchSummaries().listen((l) => events.add([for (final s in l) s.product.name]));
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final id = await repo.createProduct(input(name: 'Cola'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.updateProduct(id, input(name: 'Cola Zero'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.first, isEmpty);
      expect(events.last, ['Cola Zero']);
    });

    test('watchProduct сообщает об удалении', () async {
      final id = await repo.createProduct(input());
      final events = <ProductSummaryOrNull>[];
      final sub = repo.watchProduct(id).listen((s) => events.add(s?.product.name));
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await repo.deleteProduct(id);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.first, 'Coca-Cola 1.5L');
      expect(events.last, isNull);
    });
  });

  test('миграция: таблицы товаров существуют в схеме', () async {
    expect(db.schemaVersion, 7);
    expect(await db.select(db.products).get(), isEmpty);
    expect(await db.select(db.productPhotos).get(), isEmpty);
  });
}

typedef ProductSummaryOrNull = String?;
