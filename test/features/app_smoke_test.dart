import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/app.dart';
import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(AppSettingsSnapshot(locale: locale)),
      ],
      child: const AlSavdogarApp(),
    ));
  }

  testWidgets('splash → вкладки, переключение и смена языка', (tester) async {
    await pumpApp(tester, locale: const Locale('ru'));

    // Splash.
    expect(find.text('Al-Savdogar'), findsOneWidget);
    expect(find.text('Оптовая торговля и книга должников'), findsOneWidget);

    // Через 1.8 с переходим на главный экран.
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Долги'), findsWidgets);

    // Вкладка «Ещё» → меняем язык на английский.
    await tester.tap(find.text('Ещё'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Debts'), findsWidgets);

    // Выбор сохранён в БД.
    expect((await SettingsRepository(db).load()).locale, const Locale('en'));
  });
}
