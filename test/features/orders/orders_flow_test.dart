import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/app.dart';
import 'package:al_savdogar/features/shell/glass_nav_bar.dart';
import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/domain/debt_kind.dart';
import 'package:al_savdogar/core/domain/order_status.dart';
import 'package:al_savdogar/core/domain/product_unit.dart';
import 'package:al_savdogar/core/domain/shop_role.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';
import 'package:al_savdogar/features/catalog/data/products_repository.dart';
import 'package:al_savdogar/features/debts/data/debtors_repository.dart';
import 'package:al_savdogar/features/orders/data/orders_repository.dart';
import 'package:al_savdogar/features/orders/domain/order_models.dart';
import 'package:al_savdogar/features/profile/shop_profile_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openOrders(WidgetTester tester, {ShopRole role = ShopRole.wholesaler}) async {
    tester.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => ShopProfileRepository(db).create(name: 'Baraka Trade', roles: {role}));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
      ],
      child: const AlSavdogarApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(GlassNavBar), matching: find.byTooltip('Заказы')));
    await settle(tester);
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> tap(WidgetTester tester, Finder finder, {bool async = false}) async {
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

  /// Кнопка внутри открытого диалога (на карточке заказа бывает кнопка с тем же текстом).
  Finder dialogButton(String text) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, text),
      );

  Future<String> addCustomer(WidgetTester tester, String name, {List<String> phones = const []}) async =>
      (await tester.runAsync(() => DebtorsRepository(db).createDebtor(DebtorInput(name: name, phones: phones))))!;

  Future<String> addProduct(
    WidgetTester tester,
    String name, {
    int price = 10000,
    PackInput? pack,
    int minOrder = 1,
    bool inStock = true,
  }) async =>
      (await tester.runAsync(() => ProductsRepository(db).createProduct(ProductInput(
        name: name,
        unit: ProductUnit.piece,
        unitPrice: price,
        pack: pack,
        minOrderQuantity: minOrder,
        inStock: inStock,
      ))))!;

  Future<String> addOrder(
    WidgetTester tester,
    String customerId, {
    List<OrderItemInput> items = const [
      OrderItemInput(name: 'Cola', unit: ProductUnit.piece, quantity: 10, unitPrice: 10000),
    ],
    OrderStatus? advanceTo,
  }) async {
    final id = await tester.runAsync(() async {
      final repo = OrdersRepository(db);
      final id = await repo.createOrder(customerId: customerId, items: items, actorName: 'Baraka Trade');
      const path = [
        OrderStatus.accepted,
        OrderStatus.picking,
        OrderStatus.ready,
        OrderStatus.inTransit,
      ];
      if (advanceTo != null) {
        for (final s in path) {
          await repo.changeStatus(id, s, actorName: 'Baraka Trade');
          if (s == advanceTo) break;
        }
      }
      return id;
    });
    return id!;
  }

  testWidgets('пустой список заказов и кнопка «Новый заказ»', (tester) async {
    await openOrders(tester);
    expect(find.text('Пока нет заказов'), findsOneWidget);
    expect(find.text('Новый заказ'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('покупателю вместо заказов — заглушка', (tester) async {
    await openOrders(tester, role: ShopRole.buyer);
    expect(find.textContaining('Ваши заказы появятся здесь'), findsOneWidget);
    expect(find.text('Новый заказ'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('создание заказа: покупатель, товары, количество, цена упаковки → «Создан»', (tester) async {
    await addCustomer(tester, 'Alisher', phones: ['90 123 45 67']);
    await addProduct(tester, 'Coca-Cola', price: 12000, pack: const PackInput(kind: PackKind.box, size: 24, price: 250000));
    await addProduct(tester, 'Рис', price: 15000);
    await addProduct(tester, 'Нет в наличии', inStock: false);
    await openOrders(tester);

    await tapText(tester, 'Новый заказ');
    expect(find.text('Создать заказ'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать заказ')).onPressed, isNull);

    // Покупатель.
    await tapText(tester, 'Выберите покупателя');
    await tapText(tester, 'Alisher');
    expect(find.text('Выберите покупателя'), findsNothing);

    // Товары: «нет в наличии» не предлагается.
    await tapText(tester, 'Добавить товар');
    expect(find.text('Нет в наличии'), findsNothing);
    await tapText(tester, 'Coca-Cola');
    await tapText(tester, 'Рис');
    await tapText(tester, 'Добавить (2)');
    expect(find.text('Coca-Cola'), findsOneWidget);

    // Колу: +24 (упаковка) → ровно цена упаковки.
    await tap(tester, find.widgetWithText(ActionChip, '+24'));
    expect(find.text('1 × 24 + 1 шт'), findsOneWidget, reason: '25 штук = упаковка + 1');
    expect(find.text('262 000 сум'), findsWidgets, reason: '250 000 + 12 000');

    await tapText(tester, 'Создать заказ', async: true);

    // Карточка заказа.
    expect(find.text('Заказ №1'), findsWidgets);
    expect(find.text('Новый'), findsWidgets);
    expect(find.text('Alisher'), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);

    final order = (await tester.runAsync(() => OrdersRepository(db).loadSummaries()))!.single.order;
    expect(order.total, 262000 + 15000);
    expect(order.status, OrderStatus.created);

    await closeApp(tester);
  });

  testWidgets('новый покупатель прямо из заказа попадает в книгу должников', (tester) async {
    await addProduct(tester, 'Рис', price: 15000);
    await openOrders(tester);

    await tapText(tester, 'Новый заказ');
    await tapText(tester, 'Выберите покупателя');
    await tapText(tester, 'Новый покупатель');
    await tester.enterText(find.widgetWithText(TextFormField, 'Имя'), 'Bobur');
    await tester.enterText(find.widgetWithText(TextFormField, 'Телефон'), '93 555 11 22');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Сохранить'), async: true);

    expect(find.text('Bobur'), findsOneWidget);
    final all = await tester.runAsync(() => DebtorsRepository(db).loadSummaries());
    expect(all!.single.debtor.name, 'Bobur');
    expect(all.single.phones, ['+998935551122']);

    await closeApp(tester);
  });

  testWidgets('минимальная партия: меньше нельзя, кнопка «Создать» блокируется', (tester) async {
    await addCustomer(tester, 'Alisher');
    await addProduct(tester, 'Сахар', price: 9000, minOrder: 10);
    await openOrders(tester);

    await tapText(tester, 'Новый заказ');
    await tapText(tester, 'Выберите покупателя');
    await tapText(tester, 'Alisher');
    await tapText(tester, 'Добавить товар');
    await tapText(tester, 'Сахар');
    await tapText(tester, 'Добавить (1)');

    // По умолчанию добавляется минимальная партия.
    expect(find.text('10'), findsOneWidget);
    expect(find.textContaining('Минимум'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать заказ')).onPressed, isNotNull);

    await tap(tester, find.widgetWithIcon(IconButton, Icons.remove_rounded));
    expect(find.text('Минимум: 10 шт'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать заказ')).onPressed, isNull);

    await tap(tester, find.widgetWithIcon(IconButton, Icons.add_rounded));
    expect(find.textContaining('Минимум'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('весь путь заказа до закрытия; частичная оплата → долг в книге', (tester) async {
    final customer = await addCustomer(tester, 'Alisher');
    final orderId = await addOrder(tester, customer); // 10 × 10 000 = 100 000
    await openOrders(tester);

    await tapText(tester, 'Заказ №1');
    for (final step in ['Принять', 'Начать сборку', 'Готов к отгрузке', 'Отправить в путь']) {
      await tapText(tester, step, async: true);
    }
    expect(find.text('В пути'), findsWidgets);

    // Доставка: получено 30 000, остаток — в долг.
    await tapText(tester, 'Отметить доставку');
    expect(find.text('Оплачено полностью — долга не будет'), findsOneWidget, reason: 'по умолчанию — вся сумма');
    await tester.enterText(find.byType(TextField).last, '30000');
    await tester.pump();
    expect(find.text('Будет записано в долг: 70 000 сум'), findsOneWidget);
    await tap(tester, dialogButton('Отметить доставку'), async: true);
    expect(find.text('Долг записан в книгу должников'), findsOneWidget);
    expect(find.text('Доставлен'), findsWidgets);

    final book = await tester.runAsync(() => DebtorsRepository(db).loadDetails(customer));
    expect(book!.summary.balance, 70000);
    expect(book.transactions.map((t) => t.kind).toSet(), {DebtKind.debt, DebtKind.payment});
    expect(book.transactions.every((t) => t.orderId == orderId), isTrue);

    await tapText(tester, 'Закрыть заказ', async: true);
    expect(find.text('Закрыт'), findsWidgets);
    expect(find.text('Закрыть заказ'), findsNothing, reason: 'у закрытого заказа нет действий');

    // История: все шаги с автором.
    final details = await tester.runAsync(() => OrdersRepository(db).loadOrder(orderId));
    expect(details!.history.map((h) => h.status), [
      OrderStatus.created,
      OrderStatus.accepted,
      OrderStatus.picking,
      OrderStatus.ready,
      OrderStatus.inTransit,
      OrderStatus.delivered,
      OrderStatus.closed,
    ]);
    expect(find.textContaining('Baraka Trade'), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('полная оплата при доставке — долга в книге нет', (tester) async {
    final customer = await addCustomer(tester, 'Alisher');
    await addOrder(tester, customer, advanceTo: OrderStatus.inTransit);
    await openOrders(tester);

    await tapText(tester, 'Заказ №1');
    await tapText(tester, 'Отметить доставку');
    await tap(tester, dialogButton('Отметить доставку'), async: true);

    expect(find.text('Долг записан в книгу должников'), findsNothing);
    final book = await tester.runAsync(() => DebtorsRepository(db).loadDetails(customer));
    expect(book!.transactions, isEmpty);

    await closeApp(tester);
  });

  testWidgets('в диалоге доставки нельзя ввести больше суммы заказа', (tester) async {
    final customer = await addCustomer(tester, 'Alisher');
    await addOrder(tester, customer, advanceTo: OrderStatus.inTransit);
    await openOrders(tester);

    await tapText(tester, 'Заказ №1');
    await tapText(tester, 'Отметить доставку');
    await tester.enterText(find.byType(TextField).last, '100001');
    await tester.pump();

    expect(find.text('Больше суммы заказа'), findsOneWidget);
    final deliver = tester.widget<FilledButton>(dialogButton('Отметить доставку'));
    expect(deliver.onPressed, isNull);

    await closeApp(tester);
  });

  testWidgets('отклонение с причиной: статус, причина в истории, действий больше нет', (tester) async {
    final customer = await addCustomer(tester, 'Alisher');
    await addOrder(tester, customer);
    await openOrders(tester);

    await tapText(tester, 'Заказ №1');
    await tapText(tester, 'Отклонить');
    expect(find.text('Отклонить заказ?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Нет товара');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Удалить'), async: true);

    expect(find.text('Отклонён'), findsWidgets);
    expect(find.text('Нет товара'), findsOneWidget);
    expect(find.text('Принять'), findsNothing);
    expect(find.text('Изменить заказ'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('отмена заказа «Собирается»', (tester) async {
    final customer = await addCustomer(tester, 'Alisher');
    await addOrder(tester, customer, advanceTo: OrderStatus.picking);
    await openOrders(tester);

    await tapText(tester, 'Заказ №1');
    expect(find.text('Отклонить'), findsNothing, reason: 'отклонить можно только новый');
    expect(find.text('Изменить заказ'), findsNothing, reason: 'состав уже не меняется');
    await tapText(tester, 'Отменить заказ');
    await tap(tester, find.widgetWithText(FilledButton, 'Удалить'), async: true);

    expect(find.text('Отменён'), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('правка заказа: количество меняется, сумма пересчитывается, в истории «Заказ изменён»', (tester) async {
    final customer = await addCustomer(tester, 'Alisher');
    await addOrder(tester, customer);
    await openOrders(tester);

    await tapText(tester, 'Заказ №1');
    await tapText(tester, 'Изменить заказ');
    expect(find.text('100 000 сум'), findsWidgets);
    await tap(tester, find.widgetWithIcon(IconButton, Icons.add_rounded));
    expect(find.text('110 000 сум'), findsWidgets);
    await tap(tester, find.widgetWithText(FilledButton, 'Сохранить'), async: true);

    expect(find.text('110 000 сум'), findsWidgets);
    expect(find.text('Заказ изменён'), findsOneWidget);

    final summary = (await tester.runAsync(() => OrdersRepository(db).loadSummaries()))!.single;
    final d = await tester.runAsync(() => OrdersRepository(db).loadOrder(summary.order.id));
    expect(d!.order.total, 110000);
    expect(d.items.single.quantity, 11);

    await closeApp(tester);
  });

  testWidgets('фильтры по группам статусов', (tester) async {
    final a = await addCustomer(tester, 'Новый Клиент');
    final b = await addCustomer(tester, 'Клиент В Работе');
    await addOrder(tester, a);
    await addOrder(tester, b, advanceTo: OrderStatus.picking);
    await openOrders(tester);

    // Вкладки живут в одном дереве (имена покупателей есть и в «Долгах»), поэтому
    // проверяем по номерам заказов: №1 — новый, №2 — в работе.
    expect(find.text('Заказ №1'), findsOneWidget);
    expect(find.text('Заказ №2'), findsOneWidget);

    await tap(tester, find.widgetWithText(ChoiceChip, 'Новые'));
    expect(find.text('Заказ №1'), findsOneWidget);
    expect(find.text('Заказ №2'), findsNothing);

    await tap(tester, find.widgetWithText(ChoiceChip, 'В работе'));
    expect(find.text('Заказ №1'), findsNothing);
    expect(find.text('Заказ №2'), findsOneWidget);

    await tap(tester, find.widgetWithText(ChoiceChip, 'Закрытые'));
    expect(find.text('По этому фильтру никого нет'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('из заказа можно перейти в карточку покупателя', (tester) async {
    final customer = await addCustomer(tester, 'Alisher');
    await addOrder(tester, customer, advanceTo: OrderStatus.inTransit);
    await openOrders(tester);

    await tapText(tester, 'Заказ №1');
    await tapText(tester, 'Alisher');
    expect(find.text('Баланс'), findsOneWidget);

    await closeApp(tester);
  });
}
