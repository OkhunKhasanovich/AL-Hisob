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
import 'package:al_hisob/core/utils/dialer.dart';
import 'package:al_hisob/features/debts/data/debtors_repository.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';

void main() {
  late AppDatabase db;
  late List<String> dialed;
  var dialerWorks = true;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dialed = [];
    dialerWorks = true;
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openApp(WidgetTester tester, {String locale = 'ru'}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(AppSettingsSnapshot(locale: Locale(locale))),
        phoneDialerProvider.overrideWithValue((phone) async {
          dialed.add(phone);
          return dialerWorks;
        }),
      ],
      child: const AlHisobApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
  }

  Future<String> addDebtor(WidgetTester tester, DebtorInput input) async {
    final id = await tester.runAsync(() async {
      await ShopProfileRepository(db).create(name: 'Shop', roles: {ShopRole.wholesaler});
      return DebtorsRepository(db).createDebtor(input);
    });
    return id!;
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  group('заметка в карточке списка', () {
    testWidgets('показана прямо под именем, до телефона', (tester) async {
      await addDebtor(tester, const DebtorInput(name: 'Alisher', note: 'Рынок Чорсу, ряд 5', phones: ['901234567']));
      await openApp(tester);

      final name = tester.getRect(find.text('Alisher'));
      final note = tester.getRect(find.byKey(const ValueKey('debtor-note')));
      final phone = tester.getRect(find.text('+998 90 123 45 67'));
      expect(find.text('Рынок Чорсу, ряд 5'), findsOneWidget);
      expect(note.top, greaterThanOrEqualTo(name.bottom - 1), reason: 'под именем');
      expect(note.top, lessThan(phone.top), reason: 'выше телефона');
      expect(note.left, closeTo(name.left, 1), reason: 'того же края, что и имя');
      await closeApp(tester);
    });

    testWidgets('длинная заметка обрезается двумя строками и не ломает карточку', (tester) async {
      await addDebtor(tester, DebtorInput(name: 'Bobur', note: List.filled(40, 'очень длинная заметка').join(' ')));
      await openApp(tester);
      final note = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('debtor-note')),
        matching: find.byType(Text),
      ));
      expect(note.maxLines, 2);
      expect(note.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull, reason: 'без переполнения');
      await closeApp(tester);
    });

    testWidgets('без заметки или с пустой строки под именем нет', (tester) async {
      await addDebtor(tester, const DebtorInput(name: 'NoNote'));
      await openApp(tester);
      expect(find.byKey(const ValueKey('debtor-note')), findsNothing);
      await closeApp(tester);
    });
  });

  group('телефон в карточке должника', () {
    Future<void> openDetails(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
    }

    testWidgets('нажатие открывает набор номера с этим номером', (tester) async {
      await addDebtor(tester, const DebtorInput(name: 'Alisher', phones: ['901234567', '935551122']));
      await openApp(tester);
      await openDetails(tester, 'Alisher');

      await tester.tap(find.byKey(const ValueKey('phone-+998901234567')));
      await tester.pump();
      expect(dialed, ['+998901234567']);

      await tester.tap(find.byKey(const ValueKey('phone-+998935551122')));
      await tester.pump();
      expect(dialed, ['+998901234567', '+998935551122'], reason: 'у каждого номера свой набор');
      expect(find.byIcon(Icons.call_rounded), findsNWidgets(2));
      await closeApp(tester);
    });

    testWidgets('нет приложения для звонков — понятное сообщение', (tester) async {
      dialerWorks = false;
      await addDebtor(tester, const DebtorInput(name: 'Alisher', phones: ['901234567']));
      await openApp(tester);
      await openDetails(tester, 'Alisher');

      await tester.tap(find.byKey(const ValueKey('phone-+998901234567')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Не удалось открыть набор номера'), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('адрес и заметка по-прежнему можно выделить и скопировать', (tester) async {
      await addDebtor(tester, const DebtorInput(name: 'Alisher', address: 'Ул. Навои 5', phones: ['901234567']));
      await openApp(tester);
      await openDetails(tester, 'Alisher');
      expect(find.widgetWithText(SelectableText, 'Ул. Навои 5'), findsOneWidget);
      await closeApp(tester);
    });
  });

  group('тестовые должники', () {
    Future<void> openMore(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Ещё'));
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
    }

    testWidgets('кнопки «Добавить тестовых должников» больше нет', (tester) async {
      await addDebtor(tester, const DebtorInput(name: 'Real client'));
      await openApp(tester);
      await openMore(tester);
      expect(find.textContaining('Добавить 50'), findsNothing);
      expect(find.text('Тестовые данные'), findsNothing, reason: 'раздела нет, пока тестовых нет');
      expect(find.byIcon(Icons.science_rounded), findsNothing);
      await closeApp(tester);
    });

    testWidgets('если тестовые остались с прошлых проверок — есть только удаление, настоящие не трогаются', (tester) async {
      await addDebtor(tester, const DebtorInput(name: 'Real client'));
      await tester.runAsync(() => DebtorsRepository(db).seedDemoDebtors(count: 3));
      await openApp(tester);
      await openMore(tester);

      await tester.ensureVisible(find.text('Удалить тестовых должников'));
      await tester.pump();
      expect(find.text('Тестовые данные'), findsOneWidget);
      expect(find.text('Удалить тестовых должников'), findsOneWidget);
      expect(find.textContaining('Добавить'), findsNothing);

      await tester.tap(find.text('Удалить тестовых должников'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settle(tester);

      final left = await tester.runAsync(() => DebtorsRepository(db).loadSummaries());
      expect(left!.map((s) => s.debtor.name), ['Real client'], reason: 'остался только настоящий');
      expect(find.text('Тестовые данные'), findsNothing, reason: 'раздел исчез, когда тестовых не осталось');
      await closeApp(tester);
    });
  });

  group('«Jami qarzdorlik» при погашении', () {
    testWidgets('в узбекской версии подсказка называется «Jami qarzdorlik»', (tester) async {
      final id = await addDebtor(tester, const DebtorInput(name: 'Alisher'));
      await tester.runAsync(() => DebtorsRepository(db).addTransaction(
            debtorId: id,
            kind: DebtKind.debt,
            amount: 1500000,
            occurredAt: DateTime.now(),
          ));
      await openApp(tester, locale: 'uz');
      await tester.tap(find.text('Alisher'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);

      // Подпись кнопки погашения зависит от перевода: находим её по значку.
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);

      expect(find.textContaining('Jami qarzdorlik: 1 500 000'), findsOneWidget);
      expect(find.textContaining('Butun qarz'), findsNothing);
      await closeApp(tester);
    });
  });
}
