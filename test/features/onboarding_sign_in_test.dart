import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/app.dart';
import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/core/settings/settings_repository.dart';
import 'package:al_hisob/features/auth/data/auth_providers.dart';
import 'package:al_hisob/features/auth/domain/auth_api.dart';
import 'package:al_hisob/features/auth/presentation/login_prompt.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';
import 'package:al_hisob/features/shell/floating_nav_bar.dart';
import 'package:al_hisob/features/sync/data/sync_engine.dart';
import 'package:al_hisob/features/sync/data/sync_providers.dart';

import '../helpers/fake_auth.dart';
import '../helpers/fake_sync_api.dart';

/// Первый запуск с настроенным сервером: роли, предложение войти, «уже пользовался».
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeAuthApi auth;
  late FakeSyncApi server;
  late InMemoryTokenStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeAuthApi();
    server = FakeSyncApi();
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openApp(WidgetTester tester, {bool signedIn = false, bool serverConfigured = true}) async {
    tester.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = InMemoryTokenStore(signedIn ? fakeSession() : null);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
        serverConfiguredProvider.overrideWithValue(serverConfigured),
        authApiProvider.overrideWithValue(auth),
        tokenStoreProvider.overrideWithValue(store),
        syncApiProvider.overrideWithValue(server),
        urlOpenerProvider.overrideWithValue((_) async => true),
        loginPollDelayProvider.overrideWithValue((_) => Future<void>.delayed(const Duration(milliseconds: 20))),
      ],
      child: const AlHisobApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 1200));
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> fillAndContinue(WidgetTester tester, {String name = 'Baraka Trade', String role = 'Оптовик'}) async {
    await tester.enterText(find.byType(TextFormField), name);
    await tester.tap(find.text(role));
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Продолжить');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(button);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
  }

  /// Завершает вход: нажать «Войти через Telegram» и дождаться успеха опроса.
  Future<void> completeTelegramLogin(WidgetTester tester) async {
    auth.pollResults
      ..add(const PollPending())
      ..add(PollSuccess(fakeSession()));
    final button = find.widgetWithText(FilledButton, 'Войти через Telegram');
    await tester.runAsync(() async {
      await tester.tap(button);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    for (var i = 0; i < 8 && store.session == null; i++) {
      await settle(tester, rounds: 1);
    }
    await settle(tester);
  }

  group('роли', () {
    testWidgets('названия: «Оптовик» и «Розничный продавец», слова «Покупатель» нет', (tester) async {
      await openApp(tester);
      expect(find.text('Оптовик'), findsOneWidget);
      expect(find.text('Розничный продавец'), findsOneWidget);
      expect(find.text('Покупатель'), findsNothing);
      await closeApp(tester);
    });

    testWidgets('старое значение роли в БД читается как «Розничный продавец»', (tester) async {
      // В БД и на сервере роль по-прежнему хранится как `buyer`.
      await tester.runAsync(
        () => ShopProfileRepository(db).create(name: 'Old shop', roles: {ShopRole.buyer}),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
        ],
        child: const AlHisobApp(),
      ));
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump(const Duration(milliseconds: 800));
      await settle(tester);
      await tester.tap(find.byTooltip('Ещё'));
      await settle(tester);
      expect(find.text('Розничный продавец'), findsOneWidget);
      await closeApp(tester);
    });
  });

  group('вход на первом запуске', () {
    testWidgets('после выбора роли предлагается войти через Telegram; «Позже» ведёт в приложение', (tester) async {
      await openApp(tester);
      await fillAndContinue(tester);

      expect(find.text('Войдите через Telegram'), findsOneWidget);
      expect(find.text('Данные в сохранности, даже если потеряете телефон'), findsOneWidget);
      expect(find.byType(FloatingNavBar), findsNothing);

      await tester.tap(find.text('Позже'));
      await settle(tester);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      expect(store.session, isNull, reason: 'без входа тоже можно');
      await closeApp(tester);
    });

    testWidgets('вход из этого шага: после успеха — главный экран, профиль сохранён', (tester) async {
      await openApp(tester);
      await fillAndContinue(tester);
      expect(find.text('Войдите через Telegram'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Войти через Telegram'));
      await settle(tester);
      expect(find.text('Вход'), findsOneWidget, reason: 'открылся экран входа');

      await completeTelegramLogin(tester);

      expect(store.session, isNotNull);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      final profile = await tester.runAsync(() => ShopProfileRepository(db).current());
      expect(profile!.name, 'Baraka Trade');
      await closeApp(tester);
    });

    testWidgets('уже вошедшему шаг входа не показывается', (tester) async {
      await openApp(tester, signedIn: true);
      expect(find.text('Уже пользовались Al-Hisob?'), findsNothing, reason: 'вошёл — и так всё подтянется');
      await fillAndContinue(tester);
      expect(find.text('Войдите через Telegram'), findsNothing);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('без сервера: ни шага входа, ни кнопки «уже пользовался»', (tester) async {
      await openApp(tester, serverConfigured: false);
      expect(find.text('Уже пользовались Al-Hisob?'), findsNothing);
      await fillAndContinue(tester);
      expect(find.text('Войдите через Telegram'), findsNothing);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      await closeApp(tester);
    });
  });

  group('«Уже пользовались»', () {
    /// Данные «с другого телефона»: профиль и должник уже лежат на сервере.
    Future<void> seedServerFromOtherPhone(WidgetTester tester) async {
      await tester.runAsync(() async {
        final other = AppDatabase(NativeDatabase.memory());
        await ShopProfileRepository(other).create(name: 'Shop from phone A', roles: {ShopRole.buyer});
        await SyncEngine(db: other, api: server).run(accessToken: 't', userId: 'user-1');
        await other.close();
      });
    }

    testWidgets('вход подтягивает профиль с сервера и сразу открывает приложение', (tester) async {
      await seedServerFromOtherPhone(tester);
      await openApp(tester);
      expect(find.text('Уже пользовались Al-Hisob?'), findsOneWidget);

      await tester.ensureVisible(find.text('Войти и загрузить мои данные'));
      await tester.pump();
      await tester.tap(find.text('Войти и загрузить мои данные'));
      await settle(tester);
      await completeTelegramLogin(tester);
      for (var i = 0; i < 6 && find.byType(FloatingNavBar).evaluate().isEmpty; i++) {
        await settle(tester, rounds: 1);
      }

      expect(find.byType(FloatingNavBar), findsOneWidget, reason: 'профиль нашёлся — онбординг пропущен');
      final profile = await tester.runAsync(() => ShopProfileRepository(db).current());
      expect(profile!.name, 'Shop from phone A');
      expect(profile.roles, {ShopRole.buyer});
      await closeApp(tester);
    });

    testWidgets('у аккаунта данных нет: остаёмся на форме, вход выполнен, подсказка показана', (tester) async {
      await openApp(tester);
      await tester.ensureVisible(find.text('Войти и загрузить мои данные'));
      await tester.pump();
      await tester.tap(find.text('Войти и загрузить мои данные'));
      await settle(tester);
      await completeTelegramLogin(tester);
      for (var i = 0; i < 6 && find.byType(SnackBar).evaluate().isEmpty; i++) {
        await settle(tester, rounds: 1);
      }

      expect(store.session, isNotNull);
      expect(find.byType(FloatingNavBar), findsNothing);
      expect(find.text('Добро пожаловать!'), findsOneWidget);
      expect(find.textContaining('данных пока нет'), findsOneWidget);
      expect(find.text('Уже пользовались Al-Hisob?'), findsNothing, reason: 'уже вошли');

      // Дальше обычное создание профиля, а шаг входа пропускается: вход уже есть.
      await fillAndContinue(tester, name: 'New shop');
      expect(find.text('Войдите через Telegram'), findsNothing);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      await closeApp(tester);
    });
  });
}
