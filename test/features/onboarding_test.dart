import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/app.dart';
import 'package:al_hisob/features/shell/floating_nav_bar.dart';
import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/core/settings/settings_repository.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          initialSettingsProvider
              .overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
        ],
        child: const AlHisobApp(),
      ));

  Future<void> pastSplash(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 1200));
  }

  FilledButton continueButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('без профиля после splash открывается онбординг; кнопка активна только при валидных данных',
      (tester) async {
    await pumpApp(tester);
    await pastSplash(tester);

    expect(find.text('Добро пожаловать!'), findsOneWidget);
    expect(find.byType(FloatingNavBar), findsNothing);
    expect(continueButton(tester).onPressed, isNull);

    // Только название — роль не выбрана.
    await tester.enterText(find.byType(TextFormField), 'Baraka Trade');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);

    // Роль выбрана, но название слишком короткое.
    await tester.enterText(find.byType(TextFormField), 'B');
    await tester.tap(find.text('Покупатель'));
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);
    expect(find.text('Введите от 2 до 60 символов'), findsOneWidget);
  });

  testWidgets('прохождение онбординга сохраняет профиль и открывает главный экран',
      (tester) async {
    await pumpApp(tester);
    await pastSplash(tester);

    await tester.enterText(find.byType(TextFormField), '  Baraka   Trade ');
    await tester.tap(find.text('Оптовик'));
    await tester.pump();
    expect(continueButton(tester).onPressed, isNotNull);

    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byType(FilledButton));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(FloatingNavBar), findsOneWidget);

    final profile = await tester.runAsync(() => ShopProfileRepository(db).current());
    expect(profile!.name, 'Baraka Trade');
    expect(profile.roles, {ShopRole.wholesaler});
  });

  testWidgets('при повторном запуске онбординг пропускается', (tester) async {
    await tester.runAsync(
      () => ShopProfileRepository(db).create(name: 'Baraka', roles: {ShopRole.buyer}),
    );
    await pumpApp(tester);
    await pastSplash(tester);

    expect(find.text('Добро пожаловать!'), findsNothing);
    expect(find.byType(FloatingNavBar), findsOneWidget);
  });

  testWidgets('профиль можно изменить на вкладке «Ещё»', (tester) async {
    await tester.runAsync(
      () => ShopProfileRepository(db).create(name: 'Baraka', roles: {ShopRole.buyer}),
    );
    await pumpApp(tester);
    await pastSplash(tester);

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Baraka'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump(); // запуск анимации шторки
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextFormField), 'Yangi Baraka');
    await tester.tap(find.text('Оптовик'));
    await tester.pump();
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Сохранить'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    final profile = await tester.runAsync(() => ShopProfileRepository(db).current());
    expect(profile!.name, 'Yangi Baraka');
    expect(profile.roles, {ShopRole.wholesaler});
    expect(find.text('Yangi Baraka'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
