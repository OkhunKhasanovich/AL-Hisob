import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/app.dart';
import 'package:al_savdogar/features/shell/floating_nav_bar.dart';
import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/domain/product_unit.dart';
import 'package:al_savdogar/core/domain/shop_role.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';
import 'package:al_savdogar/features/catalog/data/catalog_providers.dart';
import 'package:al_savdogar/features/catalog/data/products_repository.dart';
import 'package:al_savdogar/features/profile/shop_profile_repository.dart';

import '../../helpers/fake_photo_picker.dart';

void main() {
  late AppDatabase db;
  late Directory photoDir;
  late Directory pickedDir;
  late FakePhotoPicker picker;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    photoDir = await Directory.systemTemp.createTemp('catalog_photos');
    pickedDir = await Directory.systemTemp.createTemp('catalog_picked');
    picker = FakePhotoPicker(pickedDir);
  });

  tearDown(() async {
    await photoDir.delete(recursive: true);
    await pickedDir.delete(recursive: true);
    await db.close();
  });

  List<String> storedFiles() => photoDir.existsSync()
      ? photoDir.listSync().map((e) => e.uri.pathSegments.last).toList()
      : <String>[];

  /// Вертикальная прокручиваемая область верхнего экрана (горизонтальные ленты фото не подходят).
  Finder verticalScrollable() {
    for (final key in const ['product-form-list', 'product-details-list']) {
      final list = find.byKey(ValueKey(key));
      if (list.evaluate().isNotEmpty) {
        return find.descendant(of: list, matching: find.byType(Scrollable)).first;
      }
    }
    return find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).last;
  }

  Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openCatalog(WidgetTester tester, {ShopRole role = ShopRole.wholesaler}) async {
    // Высокий экран, чтобы вся сетка товаров помещалась и строилась (список ленивый).
    tester.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(
        () => ShopProfileRepository(db).create(name: 'Baraka Trade', roles: {role}));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider
            .overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
        photoDirectoryProvider.overrideWith((ref) async => photoDir),
        photoPickerProvider.overrideWithValue(picker),
      ],
      child: const AlSavdogarApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(FloatingNavBar), matching: find.byTooltip('Каталог')));
    await settle(tester);
  }

  /// Прокручивает список на карточке товара (внутри есть ещё горизонтальная галерея).
  Future<void> scrollDetailsTo(WidgetTester tester, Finder target) => tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('product-details-list')),
          matching: find.byType(Scrollable),
        ).first,
        maxScrolls: 20,
      );

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> tap(WidgetTester tester, Finder finder, {bool async = false}) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200,
          scrollable: verticalScrollable(), maxScrolls: 40);
    }
    await tester.ensureVisible(finder.first);
    await tester.pump();
    if (async) {
      await tester.runAsync(() async {
        await tester.tap(finder.first);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
    } else {
      await tester.tap(finder.first);
    }
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text, {bool async = false}) =>
      tap(tester, find.text(text), async: async);

  Future<void> enter(WidgetTester tester, String label, String text) async {
    final field = find.widgetWithText(TextFormField, label);
    if (field.evaluate().isEmpty) {
      await tester.scrollUntilVisible(field, 200,
          scrollable: verticalScrollable(), maxScrolls: 40);
    }
    await tester.ensureVisible(field.first);
    await tester.enterText(field.first, text);
    await tester.pump();
  }

  Future<String> addProduct(
    WidgetTester tester,
    String name, {
    String? category,
    int price = 1000,
    PackInput? pack,
    bool inStock = true,
    List<String> photos = const [],
  }) async {
    final id = await tester.runAsync(() => ProductsRepository(db).createProduct(
          ProductInput(
            name: name,
            category: category,
            unit: ProductUnit.piece,
            unitPrice: price,
            pack: pack,
            inStock: inStock,
          ),
          photoFiles: photos,
        ));
    return id!;
  }

  testWidgets('пустой каталог оптовика: подсказка и кнопка добавления', (tester) async {
    await openCatalog(tester);
    expect(find.text('Пока нет товаров'), findsOneWidget);
    expect(find.text('Добавить товар'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('покупатель видит заглушку, а не управление каталогом', (tester) async {
    await openCatalog(tester, role: ShopRole.buyer);
    expect(find.textContaining('Каталоги оптовиков появятся здесь'), findsOneWidget);
    expect(find.text('Добавить товар'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('создание товара с упаковкой и фото → карточка с ценами', (tester) async {
    await openCatalog(tester);
    await tapText(tester, 'Добавить товар');

    // Фото с камеры.
    await tapText(tester, 'Сфотографировать', async: true);
    expect(picker.cameraCalls, 1);
    expect(find.text('Фото (1 из 5)'), findsOneWidget);
    expect(find.text('Обложка'), findsOneWidget);
    expect(storedFiles(), hasLength(1));

    await enter(tester, 'Название товара', 'Coca-Cola 1.5L');
    await enter(tester, 'Категория (необязательно)', 'Напитки');
    await enter(tester, 'Цена за единицу / шт', '12000');
    expect(find.text('12 000'), findsOneWidget, reason: 'сумма группируется при вводе');

    // Упаковка: коробка по умолчанию, 24 шт за 250 000.
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await enter(tester, 'Единиц в упаковке', '24');
    await enter(tester, 'Цена за упаковку', '250000');
    expect(find.textContaining('10 417 сум за единицу в упаковке'), findsOneWidget);
    expect(find.textContaining('На 13% дешевле, чем поштучно'), findsOneWidget);

    await enter(tester, 'Минимальная партия', '12');

    await tapText(tester, 'Сохранить', async: true);

    // Карточка товара (в тестовом окне 800×600 фото занимает экран — прокручиваем вниз).
    await scrollDetailsTo(tester, find.text('Мин. партия: 12 шт'));
    expect(find.text('Coca-Cola 1.5L'), findsWidgets);
    expect(find.text('12 000 сум / шт'), findsOneWidget);
    expect(find.text('Коробка · 24 шт'), findsOneWidget);
    expect(find.text('250 000 сум'), findsOneWidget);
    expect(find.text('На 13% дешевле, чем поштучно'), findsOneWidget);
    expect(find.text('Мин. партия: 12 шт'), findsOneWidget);
    expect(find.text('Напитки'), findsOneWidget);

    final saved = await tester.runAsync(() => ProductsRepository(db).loadSummaries());
    expect(saved!.single.photos.single.fileName, storedFiles().single);

    await closeApp(tester);
  });

  testWidgets('проверка ввода: без названия и цены товар не сохраняется', (tester) async {
    await openCatalog(tester);
    await tapText(tester, 'Добавить товар');

    await tapText(tester, 'Сохранить');

    expect(find.text('Введите название товара'), findsOneWidget);
    expect(find.text('Введите цену'), findsOneWidget);
    final all = await tester.runAsync(() => ProductsRepository(db).loadSummaries());
    expect(all, isEmpty);

    await closeApp(tester);
  });

  testWidgets('упаковка: размер меньше 2 отклоняется', (tester) async {
    await openCatalog(tester);
    await tapText(tester, 'Добавить товар');
    await enter(tester, 'Название товара', 'X');
    await enter(tester, 'Цена за единицу / шт', '100');
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await enter(tester, 'Единиц в упаковке', '1');
    await enter(tester, 'Цена за упаковку', '90');

    await tapText(tester, 'Сохранить');

    expect(find.text('Введите число от 2'), findsOneWidget);
    expect(await tester.runAsync(() => ProductsRepository(db).loadSummaries()), isEmpty);

    await closeApp(tester);
  });

  testWidgets('несколько фото из галереи, обложка и удаление; лимит 5', (tester) async {
    await openCatalog(tester);
    await tapText(tester, 'Добавить товар');

    await tapText(tester, 'Выбрать из галереи', async: true);
    expect(picker.lastGalleryLimit, 5);
    expect(find.text('Фото (3 из 5)'), findsOneWidget);

    await tapText(tester, 'Выбрать из галереи', async: true);
    expect(picker.lastGalleryLimit, 2, reason: 'в галерее предлагается не больше свободных мест');
    expect(find.text('Фото (5 из 5)'), findsOneWidget);
    expect(find.text('Сфотографировать'), findsNothing, reason: 'лимит достигнут — кнопок добавления нет');
    expect(storedFiles(), hasLength(5));

    // Убираем одно новое фото: файл удаляется сразу.
    await tap(tester, find.byIcon(Icons.more_vert_rounded).last);
    await tapText(tester, 'Убрать фото');
    expect(find.text('Фото (4 из 5)'), findsOneWidget);
    expect(storedFiles(), hasLength(4));

    await closeApp(tester);
  });

  testWidgets('закрыли форму без сохранения — добавленные файлы удалены', (tester) async {
    await openCatalog(tester);
    await tapText(tester, 'Добавить товар');
    await tapText(tester, 'Сфотографировать', async: true);
    expect(storedFiles(), hasLength(1));

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));

    expect(storedFiles(), isEmpty);
    expect(await tester.runAsync(() => ProductsRepository(db).loadSummaries()), isEmpty);

    await closeApp(tester);
  });

  testWidgets('отмена камеры ничего не добавляет', (tester) async {
    picker.cancel = true;
    await openCatalog(tester);
    await tapText(tester, 'Добавить товар');
    await tapText(tester, 'Сфотографировать', async: true);

    expect(find.text('Фото (0 из 5)'), findsOneWidget);
    expect(storedFiles(), isEmpty);

    await closeApp(tester);
  });

  testWidgets('поиск с транслитерацией и опечатками, фильтр по категории', (tester) async {
    await addProduct(tester, 'Coca-Cola 1.5L', category: 'Напитки');
    await addProduct(tester, 'Pepsi 1L', category: 'Напитки');
    await addProduct(tester, 'Гречка', category: 'Крупы');
    await openCatalog(tester);

    expect(find.text('Coca-Cola 1.5L'), findsOneWidget);
    expect(find.text('Гречка'), findsOneWidget);

    // Категория.
    await tap(tester, find.widgetWithText(ChoiceChip, 'Крупы'));
    expect(find.text('Гречка'), findsOneWidget);
    expect(find.text('Pepsi 1L'), findsNothing);
    await tap(tester, find.widgetWithText(ChoiceChip, 'Все'));

    // Поиск: латиницей находим кириллицу, с опечаткой.
    Future<void> search(String q) async {
      await tester.enterText(find.byType(SearchBar), q);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
    }

    await search('Grehcka');
    expect(find.text('Гречка'), findsOneWidget);
    expect(find.text('Pepsi 1L'), findsNothing);

    await search('Кока кола');
    expect(find.text('Coca-Cola 1.5L'), findsOneWidget);

    await search('Zzzzzz');
    expect(find.text('Ничего не найдено'), findsOneWidget);

    await tester.tap(find.byTooltip('Очистить'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pepsi 1L'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('нет в наличии: переключатель в карточке, бейдж в каталоге', (tester) async {
    await addProduct(tester, 'Fanta', price: 9000);
    await openCatalog(tester);
    expect(find.text('Нет в наличии'), findsNothing);

    await tapText(tester, 'Fanta');
    await scrollDetailsTo(tester, find.byType(Switch));
    await tap(tester, find.byType(Switch), async: true);
    final stored = await tester.runAsync(() => ProductsRepository(db).loadSummaries());
    expect(stored!.single.product.inStock, isFalse);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('Нет в наличии'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('редактирование: цена меняется, убранное фото удаляется с диска', (tester) async {
    final file = await tester.runAsync(() async {
      final f = File('${photoDir.path}/old.jpg');
      await f.create(recursive: true);
      await f.writeAsBytes([1, 2, 3]);
      return 'old.jpg';
    });
    await addProduct(tester, 'Fanta', price: 9000, photos: [file!]);
    await openCatalog(tester);

    await tapText(tester, 'Fanta');
    await tester.tap(find.byTooltip('Изменить'));
    await settle(tester);

    await enter(tester, 'Цена за единицу / шт', '9500');
    await tap(tester, find.byIcon(Icons.more_vert_rounded).first);
    await tapText(tester, 'Убрать фото');
    expect(storedFiles(), ['old.jpg'], reason: 'старый файл удаляется только после сохранения');

    await tapText(tester, 'Сохранить', async: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));

    expect(find.text('9 500 сум / шт'), findsOneWidget);
    expect(storedFiles(), isEmpty);
    final stored = await tester.runAsync(() => ProductsRepository(db).loadSummaries());
    expect(stored!.single.product.unitPrice, 9500);
    expect(stored.single.photos, isEmpty);

    await closeApp(tester);
  });

  testWidgets('удаление товара из карточки: скрыт в каталоге, файлы фото удалены', (tester) async {
    final file = await tester.runAsync(() async {
      final f = File('${photoDir.path}/p.jpg');
      await f.create(recursive: true);
      await f.writeAsBytes([1]);
      return 'p.jpg';
    });
    await addProduct(tester, 'Sprite', photos: [file!]);
    await openCatalog(tester);

    await tapText(tester, 'Sprite');
    await tester.tap(find.byTooltip('Удалить'));
    await settle(tester);
    expect(find.text('Удалить товар?'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Удалить'), async: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await settle(tester);

    expect(find.text('Пока нет товаров'), findsOneWidget);
    expect(storedFiles(), isEmpty);
    expect(await tester.runAsync(() => ProductsRepository(db).loadSummaries()), isEmpty);

    await closeApp(tester);
  });
}
