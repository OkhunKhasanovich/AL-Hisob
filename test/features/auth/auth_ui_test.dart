import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/app.dart';
import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/domain/shop_role.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';
import 'package:al_savdogar/features/auth/data/auth_providers.dart';
import 'package:al_savdogar/features/auth/domain/auth_api.dart';
import 'package:al_savdogar/features/auth/domain/login_prompt_logic.dart';
import 'package:al_savdogar/features/auth/presentation/login_prompt.dart';
import 'package:al_savdogar/features/debts/data/debtors_repository.dart';
import 'package:al_savdogar/features/profile/shop_profile_repository.dart';

import '../../helpers/fake_auth.dart';

void main() {
  late AppDatabase db;
  late FakeAuthApi api;
  late InMemoryTokenStore store;
  late List<Uri> opened;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeAuthApi();
    opened = [];
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// [promptAfterDays]: 0 — предложение доступно сразу; по умолчанию — настоящие 3 дня.
  Future<void> openApp(
    WidgetTester tester, {
    bool server = true,
    bool signedIn = false,
    int? promptAfterDays,
    bool withDebtor = true,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = InMemoryTokenStore(signedIn ? fakeSession() : null);
    await tester.runAsync(() async {
      await ShopProfileRepository(db).create(name: 'Shop', roles: {ShopRole.wholesaler});
      if (withDebtor) await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Alisher'));
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
        serverConfiguredProvider.overrideWithValue(server),
        authApiProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
        loginPollDelayProvider.overrideWithValue((_) => Future<void>.delayed(const Duration(milliseconds: 20))),
        if (promptAfterDays != null)
          loginPromptConfigProvider.overrideWith(
            (ref) async => LoginPromptConfig(afterDays: promptAfterDays, afterRecords: 1000),
          ),
      ],
      child: const AlSavdogarApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
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

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.byTooltip('Ещё')));
    await settle(tester);
  }

  group('предложение войти', () {
    testWidgets('сразу после установки не показывается', (tester) async {
      await openApp(tester);
      expect(find.text('Не потеряйте данные'), findsNothing);
      await closeApp(tester);
    });

    testWidgets('когда пора — показывается на экране «Долги»', (tester) async {
      await openApp(tester, promptAfterDays: 0);
      expect(find.text('Не потеряйте данные'), findsOneWidget);
      expect(find.text('Войти'), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('показывается и в пустой книге', (tester) async {
      await openApp(tester, promptAfterDays: 0, withDebtor: false);
      expect(find.text('Не потеряйте данные'), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('«Позже» убирает предложение и запоминает на 3 дня', (tester) async {
      await openApp(tester, promptAfterDays: 0);
      await tap(tester, find.text('Позже'), async: true);

      expect(find.text('Не потеряйте данные'), findsNothing);
      final ms = await tester.runAsync(() => SettingsRepository(db).readInt('login_prompt_snoozed_until_ms'));
      final until = DateTime.fromMillisecondsSinceEpoch(ms!);
      expect(until.difference(DateTime.now()).inHours, inInclusiveRange(70, 72));

      await closeApp(tester);
    });

    testWidgets('отложенное предложение не возвращается при следующем запуске', (tester) async {
      await tester.runAsync(() => SettingsRepository(db).writeInt(
            'login_prompt_snoozed_until_ms',
            DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
          ));
      await openApp(tester, promptAfterDays: 0);
      expect(find.text('Не потеряйте данные'), findsNothing);
      await closeApp(tester);
    });

    testWidgets('срок откладывания прошёл — предложение вернулось', (tester) async {
      await tester.runAsync(() => SettingsRepository(db).writeInt(
            'login_prompt_snoozed_until_ms',
            DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
          ));
      await openApp(tester, promptAfterDays: 0);
      expect(find.text('Не потеряйте данные'), findsOneWidget);
      await closeApp(tester);
    });

    testWidgets('вошедшему не показывается', (tester) async {
      await openApp(tester, promptAfterDays: 0, signedIn: true);
      expect(find.text('Не потеряйте данные'), findsNothing);
      await closeApp(tester);
    });

    testWidgets('без настроенного сервера не показывается и нет блока «Аккаунт»', (tester) async {
      await openApp(tester, promptAfterDays: 0, server: false);
      expect(find.text('Не потеряйте данные'), findsNothing);
      await openMore(tester);
      expect(find.text('Аккаунт'), findsNothing);
      await closeApp(tester);
    });

    testWidgets('«Войти» открывает экран входа', (tester) async {
      await openApp(tester, promptAfterDays: 0);
      await tap(tester, find.widgetWithText(FilledButton, 'Войти'));
      expect(find.text('Войти через Telegram'), findsOneWidget);
      await closeApp(tester);
    });
  });

  group('вход через Telegram', () {
    testWidgets('полный путь: бот открывается, ждём, вошли, вернулись с сообщением', (tester) async {
      await openApp(tester, promptAfterDays: 0);
      await tap(tester, find.widgetWithText(FilledButton, 'Войти'));

      api.pollResults
        ..add(const PollPending())
        ..add(const PollPending())
        ..add(PollSuccess(fakeSession()));
      await tap(tester, find.text('Войти через Telegram'), async: true);

      expect(opened.single.toString(), 'https://t.me/TestBot?start=abc');
      // ждём, пока опрос дойдёт до успеха
      for (var i = 0; i < 6 && store.session == null; i++) {
        await settle(tester, rounds: 1);
      }
      await settle(tester);

      expect(store.session, isNotNull);
      expect(find.text('Вы вошли как +998 90 123 45 67'), findsOneWidget);
      expect(find.text('Войти через Telegram'), findsNothing, reason: 'вернулись на предыдущий экран');
      expect(find.text('Не потеряйте данные'), findsNothing, reason: 'вошли — предложение исчезло');

      await closeApp(tester);
    });

    testWidgets('ожидание: можно открыть Telegram снова и отменить', (tester) async {
      await openApp(tester, promptAfterDays: 0);
      await tap(tester, find.widgetWithText(FilledButton, 'Войти'));
      await tap(tester, find.text('Войти через Telegram'), async: true);

      expect(find.text('Ждём подтверждения в Telegram…'), findsOneWidget);
      await tap(tester, find.text('Открыть Telegram снова'));
      expect(opened, hasLength(2));

      await tap(tester, find.text('Отмена'));
      expect(find.text('Войти через Telegram'), findsOneWidget);
      expect(find.text('Ждём подтверждения в Telegram…'), findsNothing);
      final calls = api.pollCalls;
      await settle(tester);
      expect(api.pollCalls, calls, reason: 'после отмены сервер больше не опрашивается');

      await closeApp(tester);
    });

    testWidgets('сервер недоступен: понятная ошибка, можно повторить', (tester) async {
      api.startResult = AuthApiException('network');
      await openApp(tester, promptAfterDays: 0);
      await tap(tester, find.widgetWithText(FilledButton, 'Войти'));
      await tap(tester, find.text('Войти через Telegram'), async: true);

      expect(find.text('Нет связи с сервером. Проверьте интернет и попробуйте ещё раз.'), findsOneWidget);
      expect(find.text('Войти через Telegram'), findsOneWidget);

      api.startResult = AuthApiException('rate_limited', status: 429);
      await tap(tester, find.text('Войти через Telegram'), async: true);
      expect(find.text('Слишком много попыток. Подождите минуту.'), findsOneWidget);

      await closeApp(tester);
    });

    testWidgets('время входа истекло', (tester) async {
      api.pollResults.add(AuthApiException('expired', status: 410));
      await openApp(tester, promptAfterDays: 0);
      await tap(tester, find.widgetWithText(FilledButton, 'Войти'));
      await tap(tester, find.text('Войти через Telegram'), async: true);
      for (var i = 0; i < 4; i++) {
        await settle(tester, rounds: 1);
      }
      expect(find.text('Время входа истекло. Попробуйте ещё раз.'), findsOneWidget);
      await closeApp(tester);
    });
  });

  group('аккаунт во вкладке «Ещё»', () {
    testWidgets('не вошли: подсказка и кнопка «Войти»', (tester) async {
      await openApp(tester);
      await openMore(tester);

      expect(find.text('Аккаунт'), findsOneWidget);
      expect(find.text('Не вошли — данные только на этом телефоне'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Войти'));
      expect(find.text('Войти через Telegram'), findsOneWidget);

      await closeApp(tester);
    });

    testWidgets('вошли: виден номер; «Выйти» с подтверждением закрывает сессию', (tester) async {
      await openApp(tester, signedIn: true);
      await openMore(tester);

      expect(find.text('Вы вошли: +998 90 123 45 67'), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, 'Выйти'));
      expect(find.text('Выйти из аккаунта?'), findsOneWidget);
      expect(find.textContaining('Данные останутся на этом телефоне'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Выйти'), async: true);

      expect(api.loggedOut, ['access-1']);
      expect(store.session, isNull);
      expect(find.text('Не вошли — данные только на этом телефоне'), findsOneWidget);

      await closeApp(tester);
    });

    testWidgets('отказ в подтверждении выхода ничего не меняет', (tester) async {
      await openApp(tester, signedIn: true);
      await openMore(tester);
      await tap(tester, find.widgetWithText(TextButton, 'Выйти'));
      await tap(tester, find.widgetWithText(TextButton, 'Отмена'));

      expect(store.session, isNotNull);
      expect(api.loggedOut, isEmpty);
      expect(find.text('Вы вошли: +998 90 123 45 67'), findsOneWidget);

      await closeApp(tester);
    });
  });
}
