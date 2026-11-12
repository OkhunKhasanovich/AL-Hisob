import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/app.dart';
import 'package:al_hisob/features/shell/floating_nav_bar.dart';
import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/core/settings/settings_repository.dart';

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
      child: const AlHisobApp(),
    ));
  }

  testWidgets('splash → вкладки, переключение и смена языка', (tester) async {
    // Онбординг уже пройден.
    await tester.runAsync(
      () => ShopProfileRepository(db).create(name: 'Baraka', roles: {ShopRole.wholesaler}),
    );
    await pumpApp(tester, locale: const Locale('ru'));

    // Splash.
    expect(find.text('Al-Hisob'), findsOneWidget);
    expect(find.text('Оптовая торговля и книга должников'), findsOneWidget);

    // Через 1.8 с переходим на главный экран.
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(find.text('Долги'), findsWidgets);

    // Вкладка «Ещё» → меняем язык на английский.
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Debts'), findsWidgets);

    // Карточка профиля на вкладке «Ещё».
    expect(find.text('Baraka'), findsOneWidget);

    // Выбор сохранён в БД.
    final saved = await tester.runAsync(() => SettingsRepository(db).load());
    expect(saved!.locale, const Locale('en'));

    // drift при закрытии stream создаёт zero-таймер: размонтируем и сбрасываем его.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
