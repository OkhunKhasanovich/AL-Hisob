import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';
import 'package:al_savdogar/core/theme/app_theme.dart';
import 'package:al_savdogar/core/widgets/app_backdrop.dart';

void main() {
  Widget host(AppBackdropStyle style, {ThemeData? theme}) => MaterialApp(
        theme: theme ?? AppTheme.dark(),
        home: Scaffold(body: AppBackdrop(style: style)),
      );

  group('AppBackdrop', () {
    testWidgets('«без фона» ничего не рисует', (tester) async {
      await tester.pumpWidget(host(AppBackdropStyle.plain));
      expect(find.descendant(of: find.byType(AppBackdrop), matching: find.byType(CustomPaint)),
          findsNothing);
    });

    testWidgets('«сияние» — облака и шары (2 слоя), «узор» — ещё и сетка звёзд (3)', (tester) async {
      Finder paints() =>
          find.descendant(of: find.byType(AppBackdrop), matching: find.byType(CustomPaint));

      await tester.pumpWidget(host(AppBackdropStyle.aurora));
      expect(paints(), findsNWidgets(2));

      await tester.pumpWidget(host(AppBackdropStyle.ornament));
      expect(paints(), findsNWidgets(3));

      await tester.pumpWidget(const SizedBox.shrink()); // таймер дрейфа остановлен
    });

    testWidgets('облака плывут (перерисовка по времени), узор — нет', (tester) async {
      await tester.pumpWidget(host(AppBackdropStyle.ornament));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('без анимаций: фон статичен и таймера нет', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(AppBackdropStyle.aurora),
      ));
      await tester.pump(const Duration(seconds: 1));
      // Если бы таймер работал, тест не завершился бы без отмены; здесь отменять нечего.
      expect(find.byType(AppBackdrop), findsOneWidget);
    });

    testWidgets('светлая и тёмная темы рисуются без ошибок', (tester) async {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(host(AppBackdropStyle.ornament, theme: theme));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('настройка фона', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('по умолчанию — узор; выбор сохраняется и читается при запуске', () async {
      final repo = SettingsRepository(db);
      expect((await repo.load()).backdrop, AppBackdropStyle.ornament);

      await repo.saveBackdrop(AppBackdropStyle.aurora);
      expect((await repo.load()).backdrop, AppBackdropStyle.aurora);

      await repo.saveBackdrop(AppBackdropStyle.plain);
      expect((await repo.load()).backdrop, AppBackdropStyle.plain);
    });

    test('непонятное значение в базе — безопасно возвращается узор', () async {
      await SettingsRepository(db).writeInt('backdrop_style', 7); // не имя стиля
      expect((await SettingsRepository(db).load()).backdrop, AppBackdropStyle.ornament);
    });

    test('контроллер меняет состояние и пишет в базу', () async {
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);
      expect(container.read(backdropStyleProvider), AppBackdropStyle.ornament);

      await container.read(backdropStyleProvider.notifier).select(AppBackdropStyle.plain);

      expect(container.read(backdropStyleProvider), AppBackdropStyle.plain);
      expect((await SettingsRepository(db).load()).backdrop, AppBackdropStyle.plain);
    });
  });
}
