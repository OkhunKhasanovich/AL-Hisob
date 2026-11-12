import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/app.dart';
import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/debt_kind.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/core/settings/settings_repository.dart';
import 'package:al_hisob/features/debts/data/debtors_repository.dart';
import 'package:al_hisob/features/debts/presentation/transaction_sheet.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Даёт реальным async-операциям БД завершиться и прокручивает кадры.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openDebts(WidgetTester tester) async {
    await tester.runAsync(
      () => ShopProfileRepository(db).create(name: 'Shop', roles: {ShopRole.wholesaler}),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider
            .overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
      ],
      child: const AlHisobApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
  }

  /// Открывает лист фильтров (воронка в строке поиска) и выбирает пункт.
  Future<void> chooseFilter(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Фильтры'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(ListTile, label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> tapAsync(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
  }

  testWidgets('пустая книга → создание должника → операции → баланс и фильтры', (tester) async {
    await openDebts(tester);

    // Пустое состояние.
    expect(find.text('Пока нет должников'), findsOneWidget);

    // Создаём должника.
    await tester.tap(find.byTooltip('Добавить должника'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alisher');
    await tester.enterText(fields.at(2), '90 123 45 67');
    await tester.pump();
    await tapAsync(tester, find.text('Сохранить'));

    // Открылась карточка: имя, телефон, нулевой баланс.
    expect(find.text('Alisher'), findsWidgets);
    expect(find.text('+998 90 123 45 67'), findsOneWidget);
    expect(find.text('Нет долга'), findsOneWidget);
    expect(find.text('Операций пока нет'), findsOneWidget);

    // Кнопка «В долг» — коротко, в одну строку; в шторке заголовок полный.
    await tester.tap(find.text('В долг'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).first, '1500000');
    await tester.pump();
    expect(find.text('1 500 000'), findsOneWidget, reason: 'сумма группируется при вводе');
    await tapAsync(
      tester,
      find.descendant(of: find.byType(TransactionForm), matching: find.byType(FilledButton)),
    );
    expect(find.text('1 500 000 сум'), findsOneWidget);
    expect(find.text('+1 500 000'), findsOneWidget);

    // «Погашение» 500 000.
    await tester.tap(find.text('Погашение'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).first, '500000');
    await tester.pump();
    await tapAsync(
      tester,
      find.descendant(of: find.byType(TransactionForm), matching: find.byType(FilledButton)),
    );
    expect(find.text('1 000 000 сум'), findsOneWidget);
    expect(find.text('−500 000'), findsOneWidget);

    // Назад в список: должник и итог.
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(find.text('Alisher'), findsOneWidget);
    expect(find.text('1 000 000 сум'), findsNWidgets(2), reason: 'в итоге и в строке');

    // Фильтры: долг = порогу крупного (1 000 000) → виден; просроченных нет.
    await chooseFilter(tester, 'Крупные');
    expect(find.text('Alisher'), findsOneWidget);
    expect(find.text('Крупные · 1'), findsOneWidget, reason: 'включённый фильтр виден с числом результатов');
    await chooseFilter(tester, 'Просроченные');
    expect(find.text('Alisher'), findsNothing);
    expect(find.text('По этому фильтру никого нет'), findsOneWidget);
    await chooseFilter(tester, 'Все');
    expect(find.text('Alisher'), findsOneWidget);
    expect(find.textContaining(' · '), findsNothing, reason: 'фильтр снят — плашки нет');

    await closeApp(tester);
  });

  testWidgets('просроченный должник попадает в фильтр и получает бейдж', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      final id = await repo.createDebtor(const DebtorInput(name: 'Bobur'));
      await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 300000,
        occurredAt: DateTime.now().subtract(const Duration(days: 45)),
      );
    });
    await openDebts(tester);

    expect(find.text('Просрочен · 45 дн.'), findsOneWidget);
    await chooseFilter(tester, 'Просроченные');
    expect(find.text('Bobur'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('удаление должника из карточки возвращает в пустую книгу', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      final id = await repo.createDebtor(const DebtorInput(name: 'Davron'));
      await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 1000,
        occurredAt: DateTime.now(),
      );
    });
    await openDebts(tester);

    await tester.tap(find.text('Davron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Удалить должника?'), findsOneWidget);
    await tapAsync(tester, find.widgetWithText(FilledButton, 'Удалить'));
    await settle(tester);

    expect(find.text('Пока нет должников'), findsOneWidget);
    final all = await tester.runAsync(() => DebtorsRepository(db).loadSummaries());
    expect(all, isEmpty);

    await closeApp(tester);
  });

  testWidgets('поиск: кириллица ↔ латиница, опечатки, номер, очистка', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      await repo.createDebtor(const DebtorInput(name: 'Ahmad Karimov', phones: ['90 123 45 67']));
      await repo.createDebtor(const DebtorInput(name: 'Шерзод Алиев', phones: ['93 555 11 22']));
      await repo.createDebtor(const DebtorInput(name: 'Bobur'));
    });
    await openDebts(tester);
    final field = find.byType(SearchBar);

    Future<void> typeQuery(String text) async {
      await tester.enterText(field, text);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300)); // debounce 250 мс
    }

    // До ввода — все трое и итоговая карточка.
    expect(find.text('Ahmad Karimov'), findsOneWidget);
    expect(find.text('Шерзод Алиев'), findsOneWidget);
    expect(find.text('Bobur'), findsOneWidget);
    expect(find.text('Вам должны'), findsOneWidget);

    // Латиницей находим кириллицу.
    await typeQuery('Sherzod');
    expect(find.text('Шерзод Алиев'), findsOneWidget);
    expect(find.text('Ahmad Karimov'), findsNothing);
    expect(find.text('Вам должны'), findsOneWidget, reason: 'общий обзор остаётся наверху и при поиске');

    // Кириллицей находим латиницу + опечатка.
    await typeQuery('Ахмат');
    expect(find.text('Ahmad Karimov'), findsOneWidget);
    expect(find.text('Шерзод Алиев'), findsNothing);

    // Номер в любом формате: показывается найденный телефон.
    await typeQuery('+998 (93) 555');
    expect(find.text('Шерзод Алиев'), findsOneWidget);
    expect(find.text('+998 93 555 11 22'), findsOneWidget);

    // Ничего не нашлось.
    await typeQuery('Zzzzzz');
    expect(find.text('Ничего не найдено'), findsOneWidget);

    // Крестик очищает поиск и возвращает полный список.
    await tester.tap(find.byTooltip('Очистить'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Вам должны'), findsOneWidget);
    expect(find.text('Bobur'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('график динамики: индекс растущего долга на карточке обзора', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      final id = await repo.createDebtor(const DebtorInput(name: 'Alisher'));
      final now = DateTime.now();
      await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 1000,
        occurredAt: now.subtract(const Duration(days: 45)),
      );
      await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 200,
        occurredAt: now.subtract(const Duration(days: 3)),
      );
    });
    await openDebts(tester);

    expect(find.text('+20%'), findsOneWidget);
    expect(find.text('за 7 дн.'), findsOneWidget, reason: 'график недельный');

    await closeApp(tester);
  });

  testWidgets('погашение: подсказка «Весь долг» подставляет сумму; частичная оплата гасит старые долги',
      (tester) async {
    late String id;
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      id = await repo.createDebtor(const DebtorInput(name: 'Alisher'));
      await repo.addTransaction(
          debtorId: id,
          kind: DebtKind.debt,
          amount: 1000000,
          occurredAt: DateTime.now().subtract(const Duration(days: 20)));
      await repo.addTransaction(
          debtorId: id,
          kind: DebtKind.debt,
          amount: 500000,
          occurredAt: DateTime.now().subtract(const Duration(days: 5)));
    });
    await openDebts(tester);

    await tester.tap(find.text('Alisher'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('В долг'), findsOneWidget);
    expect(find.text('Погашение'), findsOneWidget);

    await tester.tap(find.text('Погашение'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Весь долг: 1 500 000 сум'), findsOneWidget);
    expect(find.text('Нажмите, чтобы подставить'), findsOneWidget);

    // Нажатие подставляет весь долг в поле суммы.
    await tester.tap(find.byKey(const ValueKey('full-debt-suggestion')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '1 500 000');

    // Вводим часть: 1 200 000.
    await tester.enterText(find.byType(TextField).first, '1200000');
    await tester.pump();
    await tapAsync(
      tester,
      find.descendant(of: find.byType(TransactionForm), matching: find.byType(FilledButton)),
    );

    // Самый старый долг (1 000 000) погашен целиком, следующий — частично.
    expect(find.text('Погашен'), findsOneWidget);
    expect(find.text('Осталось 300 000 из 500 000'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('новый должник: поле «Текущий долг» переносит сумму из тетради', (tester) async {
    await openDebts(tester);

    await tester.tap(find.byTooltip('Добавить должника'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Текущий долг (необязательно)'), findsOneWidget);
    expect(find.text('Сколько должен сейчас: перенесите из тетради'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alisher');
    await tester.enterText(find.byKey(const ValueKey('current-debt')), '2500000');
    await tester.pump();
    expect(find.text('2 500 000'), findsOneWidget, reason: 'сумма группируется при вводе');
    await tapAsync(tester, find.text('Сохранить'));

    // Открылась карточка: баланс и операция «из тетради».
    expect(find.text('2 500 000 сум'), findsWidgets);
    expect(find.textContaining('Начальный долг (из тетради)'), findsOneWidget, reason: 'комментарий операции');
    expect(find.text('+2 500 000'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('при редактировании поля «Текущий долг» нет', (tester) async {
    late String id;
    await tester.runAsync(() async {
      id = await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Bobur', initialDebt: 1000));
    });
    await openDebts(tester);
    await tester.tap(find.text('Bobur'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('Изменить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('current-debt')), findsNothing);
    expect(id, isNotEmpty);
    await closeApp(tester);
  });

  testWidgets('раскладка: обзор сверху, под ним поиск с воронкой в конце поля, чипов фильтров нет', (tester) async {
    await tester.runAsync(() => DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Alisher')));
    await openDebts(tester);

    final overviewY = tester.getTopLeft(find.text('Вам должны')).dy;
    final searchY = tester.getTopLeft(find.byType(SearchBar)).dy;
    final firstRowY = tester.getTopLeft(find.text('Alisher')).dy;
    expect(overviewY, lessThan(searchY), reason: 'карточка общего долга — самая верхняя');
    expect(searchY, lessThan(firstRowY));

    // Воронка внутри строки поиска, в её конце.
    final funnel = find.descendant(of: find.byType(SearchBar), matching: find.byTooltip('Фильтры'));
    expect(funnel, findsOneWidget);
    expect(tester.getCenter(funnel).dx, greaterThan(tester.getCenter(find.byType(SearchBar)).dx));
    expect(find.byType(ChoiceChip), findsNothing, reason: 'фильтры не занимают место отдельной строкой');

    await closeApp(tester);
  });

  testWidgets('обзор: сумма, число должников и просрочка', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      Future<void> debtor(String name, int amount, int daysAgo) async {
        final id = await repo.createDebtor(DebtorInput(name: name));
        await repo.addTransaction(
          debtorId: id,
          kind: DebtKind.debt,
          amount: amount,
          occurredAt: DateTime.now().subtract(Duration(days: daysAgo)),
        );
      }

      await debtor('Fresh', 400000, 2);
      await debtor('Old', 600000, 50);
      await repo.createDebtor(const DebtorInput(name: 'Zero'));
    });
    await openDebts(tester);

    expect(find.text('1 000 000 сум'), findsWidgets);
    Finder stat(String key, String value) =>
        find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(value));
    expect(stat('stat-debtors', '2'), findsOneWidget, reason: 'без долга не считается');
    expect(stat('stat-overdue', '1'), findsOneWidget);
    expect(find.textContaining('Должников'), findsNothing, reason: 'только значки, без слов');
    expect(find.textContaining('Просрочено'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('карточка должника информативна: магазин, телефон, операции, возврат, давность', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      final id = await repo.createDebtor(const DebtorInput(
        name: 'Alisher',
        shopName: 'Baraka Market',
        phones: ['90 123 45 67', '93 555 11 22'],
      ));
      await repo.addTransaction(
          debtorId: id, kind: DebtKind.debt, amount: 1000000, occurredAt: DateTime.now().subtract(const Duration(days: 3)));
      await repo.addTransaction(
          debtorId: id, kind: DebtKind.payment, amount: 400000, occurredAt: DateTime.now());
    });
    await openDebts(tester);

    expect(find.text('Alisher'), findsOneWidget);
    expect(
      find.text('+998 90 123 45 67  +1 • Baraka Market'),
      findsOneWidget,
      reason: 'телефон (и сколько ещё), затем • и магазин — в одну строку',
    );
    expect(find.text('600 000 сум'), findsWidgets, reason: 'текущий долг');
    expect(find.text('Сегодня'), findsOneWidget, reason: 'последняя операция — оплата сегодня');
    expect(find.text('2 опер.'), findsOneWidget);
    expect(find.text('Оплачено 40%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Просрочен'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('давность операции: вчера и «N дн. назад»', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      Future<void> debtor(String name, int daysAgo) async {
        final id = await repo.createDebtor(DebtorInput(name: name));
        await repo.addTransaction(
          debtorId: id,
          kind: DebtKind.debt,
          amount: 1000,
          occurredAt: DateTime.now().subtract(Duration(days: daysAgo)),
        );
      }

      await debtor('Yesterday', 1);
      await debtor('Week', 7);
    });
    await openDebts(tester);

    expect(find.text('Вчера'), findsOneWidget);
    expect(find.text('7 дн. назад'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('лист фильтров: пояснения к пунктам, выбор и сброс плашкой', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      final id = await repo.createDebtor(const DebtorInput(name: 'Bobur'));
      await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 300000,
        occurredAt: DateTime.now().subtract(const Duration(days: 45)),
      );
    });
    await openDebts(tester);

    await tester.tap(find.byTooltip('Фильтры'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Показать'), findsOneWidget);
    expect(find.text('Нет операций больше 30 дн.'), findsOneWidget);
    expect(find.text('Долг от 1 000 000 сум'), findsOneWidget);
    expect(find.text('Сначала недавние операции'), findsOneWidget);
    expect(find.text('Сначала самый большой долг'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Просроченные'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Просроченные · 1'), findsOneWidget);

    // Снять фильтр можно крестиком на плашке.
    await tester.tap(find.byTooltip('Сбросить фильтр'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Просроченные · 1'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('поиск сочетается с фильтром: фильтр сужает результаты, порядок — по релевантности', (tester) async {
    // Панель вкладок-«таблетка» ниже обычной: даём экран повыше, чтобы все карточки поместились.
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      Future<void> debtor(String name, int amount) async {
        final id = await repo.createDebtor(DebtorInput(name: name));
        await repo.addTransaction(debtorId: id, kind: DebtKind.debt, amount: amount, occurredAt: DateTime.now());
      }

      await debtor('Ali Small', 100000);
      await debtor('Ali Big', 5000000);
      await debtor('Vali Big', 7000000);
    });
    await openDebts(tester);

    await tester.enterText(find.byType(SearchBar), 'Ali');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    // «Ali» — начало слова в Ali…; в «Vali» это лишь часть слова, поэтому он ниже.
    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(find.text('Vali Big'), findsOneWidget);
    expect(y('Ali Big'), lessThan(y('Vali Big')), reason: 'релевантность важнее размера долга (7 млн у Vali)');
    expect(y('Ali Small'), lessThan(y('Vali Big')));

    await chooseFilter(tester, 'Крупные');
    expect(find.text('Ali Small'), findsNothing, reason: 'мелкий долг отсеян фильтром');
    expect(find.text('Ali Big'), findsOneWidget);
    expect(find.text('Vali Big'), findsOneWidget);
    expect(y('Ali Big'), lessThan(y('Vali Big')), reason: 'порядок по релевантности сохраняется');

    await closeApp(tester);
  });
}
