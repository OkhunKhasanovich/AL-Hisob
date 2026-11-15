import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/app.dart';
import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/core/settings/settings_repository.dart';
import 'package:al_hisob/core/theme/app_theme.dart';
import 'package:al_hisob/core/theme/glass_style.dart';
import 'package:al_hisob/core/theme/theme_style.dart';
import 'package:al_hisob/features/debts/data/debtors_repository.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openApp(WidgetTester tester, {AppSettingsSnapshot? settings}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await ShopProfileRepository(db).create(name: 'Shop', roles: {ShopRole.wholesaler});
      final repo = DebtorsRepository(db);
      await repo.createDebtor(const DebtorInput(name: 'Alisher', note: 'Рынок', phones: ['901234567'], initialDebt: 5000));
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(settings ?? const AppSettingsSnapshot(locale: Locale('ru'))),
      ],
      child: const AlHisobApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> openThemes(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(ListTile, 'Темы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
  }

  group('темы (данные)', () {
    test('по умолчанию обычный стиль; Liquid Glass запоминается', () async {
      final repo = SettingsRepository(db);
      expect((await repo.load()).themeStyle, ThemeStyle.classic);
      await repo.saveThemeStyle(ThemeStyle.liquidGlass);
      expect((await repo.load()).themeStyle, ThemeStyle.liquidGlass);
      await repo.saveThemeStyle(ThemeStyle.classic);
      expect((await repo.load()).themeStyle, ThemeStyle.classic);
    });

    test('в обычной теме расширения стекла нет, в стеклянной есть — и для светлой, и для тёмной', () {
      expect(AppTheme.light().extension<GlassStyle>(), isNull);
      expect(AppTheme.dark().extension<GlassStyle>(), isNull);
      expect(AppTheme.light(style: ThemeStyle.liquidGlass).extension<GlassStyle>()!.brightness, Brightness.light);
      expect(AppTheme.dark(style: ThemeStyle.liquidGlass).extension<GlassStyle>()!.brightness, Brightness.dark);
      expect(AppTheme.dark(style: ThemeStyle.liquidGlass).scaffoldBackgroundColor, Colors.transparent);
      expect(AppTheme.dark().scaffoldBackgroundColor, isNot(Colors.transparent));
    });
  });

  group('раздел «Темы»', () {
    testWidgets('в «Ещё» есть строка «Темы» с текущим стилем; она открывает раздел', (tester) async {
      await openApp(tester);
      await tester.tap(find.byTooltip('Ещё'));
      await tester.pump(const Duration(milliseconds: 500));
      final row = find.widgetWithText(ListTile, 'Темы');
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Классическая')), findsOneWidget);

      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.text('Классическая'), findsWidgets);
      expect(find.text('Liquid Glass'), findsOneWidget);
      expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget, reason: 'светлая/тёмная — здесь же');
      await closeApp(tester);
    });

    testWidgets('выбор Liquid Glass включает стиль на лету и сохраняет его', (tester) async {
      await openApp(tester);
      expect(find.byKey(const ValueKey('glass-backdrop')), findsNothing, reason: 'сначала обычный вид');

      await openThemes(tester);
      await tester.tap(find.byKey(const ValueKey('theme-style-liquidGlass')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Раздел «Темы» сам стал стеклянным: у страницы появился фон.
      expect(find.byKey(const ValueKey('glass-backdrop')), findsWidgets);
      final saved = await tester.runAsync(() => SettingsRepository(db).load());
      expect(saved!.themeStyle, ThemeStyle.liquidGlass);

      // Назад: главный экран тоже в стекле.
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('Долги'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.text('Alisher'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // И обратно на обычный.
      await tester.tap(find.byTooltip('Ещё'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.widgetWithText(ListTile, 'Темы'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('theme-style-classic')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final back = await tester.runAsync(() => SettingsRepository(db).load());
      expect(back!.themeStyle, ThemeStyle.classic);
      await closeApp(tester);
    });

    testWidgets('светлая/тёмная переключается в разделе «Темы»', (tester) async {
      await openApp(tester);
      await openThemes(tester);
      await tester.tap(find.text('Тёмная'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final saved = await tester.runAsync(() => SettingsRepository(db).load());
      expect(saved!.themeMode, ThemeMode.dark);
      await closeApp(tester);
    });
  });

  group('Liquid Glass на экранах', () {
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets('главный экран и «Ещё» собираются без ошибок (${mode.name})', (tester) async {
        await openApp(
          tester,
          settings: AppSettingsSnapshot(
            locale: const Locale('ru'),
            themeMode: mode,
            themeStyle: ThemeStyle.liquidGlass,
          ),
        );
        expect(find.byKey(const ValueKey('glass-backdrop')), findsOneWidget, reason: 'фон под страницей');
        expect(find.text('Alisher'), findsOneWidget);
        expect(find.text('Рынок'), findsOneWidget);
        expect(find.byTooltip('Ещё'), findsOneWidget);

        await tester.tap(find.byTooltip('Ещё'));
        await tester.pump(const Duration(milliseconds: 500));
        await settle(tester);
        expect(find.widgetWithText(ListTile, 'Темы'), findsOneWidget);
        expect(find.byKey(const ValueKey('glass-backdrop')), findsOneWidget);

        // Карточка должника открывается и тоже на стеклянном фоне.
        await tester.tap(find.byTooltip('Долги'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Alisher'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await settle(tester);
        expect(find.byKey(const ValueKey('glass-backdrop')), findsOneWidget, reason: 'у нижней страницы свой фон — без просвечивания');
        expect(tester.takeException(), isNull);
        await closeApp(tester);
      });
    }

    testWidgets('в обычном стиле фона-стекла нет, а текст читаем (цвета не менялись)', (tester) async {
      await openApp(tester);
      expect(find.byKey(const ValueKey('glass-backdrop')), findsNothing);
      await closeApp(tester);
    });
  });
}
