import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/auth/data/auth_providers.dart';
import 'package:al_savdogar/features/auth/domain/auth_api.dart';
import 'package:al_savdogar/features/auth/domain/auth_models.dart';
import 'package:al_savdogar/features/auth/domain/login_prompt_logic.dart';
import 'package:al_savdogar/features/auth/presentation/auth_controller.dart';
import 'package:al_savdogar/features/auth/presentation/telegram_login_controller.dart';

import '../../helpers/fake_auth.dart';

void main() {
  late FakeAuthApi api;
  late InMemoryTokenStore store;
  late List<Uri> opened;
  late bool canOpen;

  ProviderContainer container({AuthSession? stored}) {
    store = InMemoryTokenStore(stored);
    final c = ProviderContainer(overrides: [
      authApiProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(store),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return canOpen;
      }),
      loginPollDelayProvider.overrideWithValue((_) => Future<void>.delayed(Duration.zero)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    api = FakeAuthApi();
    opened = [];
    canOpen = true;
  });

  group('модели', () {
    test('сессия сериализуется туда и обратно', () {
      final s = fakeSession();
      final back = AuthSession.fromJson(s.toJson());
      expect(back.user.phone, s.user.phone);
      expect(back.user.name, 'Ali');
      expect(back.tokens.refreshToken, 'refresh-1');
      expect(back.tokens.accessExpiresAt.millisecondsSinceEpoch, s.tokens.accessExpiresAt.millisecondsSinceEpoch);
    });

    test('expiresWithin', () {
      final now = DateTime(2026, 1, 1, 12);
      final t = AuthTokens(accessToken: 'a', refreshToken: 'r', accessExpiresAt: now.add(const Duration(seconds: 20)));
      expect(t.expiresWithin(const Duration(seconds: 30), now: now), isTrue);
      expect(t.expiresWithin(const Duration(seconds: 10), now: now), isFalse);
      expect(t.expiresWithin(Duration.zero, now: now.add(const Duration(seconds: 21))), isTrue);
    });
  });

  group('вход через Telegram', () {
    test('открывает бота, опрашивает и входит; сессия сохраняется', () async {
      final c = container();
      api.pollResults
        ..add(const PollPending())
        ..add(const PollPending())
        ..add(PollSuccess(fakeSession()));

      await c.read(telegramLoginProvider.notifier).start();

      final state = c.read(telegramLoginProvider);
      expect(state.phase, LoginPhase.success);
      expect(state.user!.phone, '+998901234567');
      expect(opened.single.toString(), 'https://t.me/TestBot?start=abc');
      expect(api.pollCalls, 3);
      expect(store.session!.tokens.refreshToken, 'refresh-1');
      expect(await c.read(authControllerProvider.future), isNotNull);
      expect(c.read(currentUserProvider)!.phone, '+998901234567');
    });

    test('сервер недоступен при старте', () async {
      final c = container();
      api.startResult = AuthApiException('network');
      await c.read(telegramLoginProvider.notifier).start();
      expect(c.read(telegramLoginProvider).phase, LoginPhase.failed);
      expect(c.read(telegramLoginProvider).failure, LoginFailure.network);
      expect(opened, isEmpty);
    });

    test('коды ошибок сервера при старте', () async {
      for (final (code, status, failure) in [
        ('rate_limited', 429, LoginFailure.rateLimited),
        ('bot_not_configured', 503, LoginFailure.botNotConfigured),
        ('oops', 500, LoginFailure.server),
      ]) {
        final c = container();
        api.startResult = AuthApiException(code, status: status);
        await c.read(telegramLoginProvider.notifier).start();
        expect(c.read(telegramLoginProvider).failure, failure, reason: code);
      }
    });

    test('запрос истёк на сервере', () async {
      final c = container();
      api.pollResults.add(AuthApiException('expired', status: 410));
      await c.read(telegramLoginProvider.notifier).start();
      expect(c.read(telegramLoginProvider).failure, LoginFailure.expired);
      expect(store.session, isNull);
    });

    test('срок ожидания вышел на клиенте', () async {
      final c = container();
      api.startResult = StartedLogin(
        requestId: 'r',
        pollSecret: 's',
        botUrl: Uri.parse('https://t.me/b?start=x'),
        expiresIn: Duration.zero,
      );
      await c.read(telegramLoginProvider.notifier).start();
      expect(c.read(telegramLoginProvider).failure, LoginFailure.expired);
      expect(api.pollCalls, 0);
    });

    test('короткие обрывы связи терпятся', () async {
      final c = container();
      api.pollResults
        ..add(AuthApiException('network'))
        ..add(AuthApiException('error', status: 502))
        ..add(AuthApiException('network'))
        ..add(PollSuccess(fakeSession()));
      await c.read(telegramLoginProvider.notifier).start();
      expect(c.read(telegramLoginProvider).phase, LoginPhase.success);
    });

    test('долгий обрыв связи — ошибка сети', () async {
      final c = container();
      for (var i = 0; i < 10; i++) {
        api.pollResults.add(AuthApiException('network'));
      }
      await c.read(telegramLoginProvider.notifier).start();
      expect(c.read(telegramLoginProvider).failure, LoginFailure.network);
      expect(api.pollCalls, TelegramLoginController.maxConsecutiveNetworkErrors);
    });

    test('успешный опрос сбрасывает счётчик ошибок', () async {
      final c = container();
      for (var i = 0; i < 4; i++) {
        api.pollResults.add(AuthApiException('network'));
      }
      api.pollResults.add(const PollPending());
      for (var i = 0; i < 4; i++) {
        api.pollResults.add(AuthApiException('network'));
      }
      api.pollResults.add(PollSuccess(fakeSession()));
      await c.read(telegramLoginProvider.notifier).start();
      expect(c.read(telegramLoginProvider).phase, LoginPhase.success);
    });

    test('Telegram не открылся — ожидание продолжается с подсказкой', () async {
      final c = container();
      canOpen = false;
      api.pollResults.add(PollSuccess(fakeSession()));
      await c.read(telegramLoginProvider.notifier).start();
      // Вход всё равно завершился: человек мог открыть ссылку вручную.
      expect(c.read(telegramLoginProvider).phase, LoginPhase.success);
    });

    test('отмена останавливает опрос', () async {
      final c = container();
      final notifier = c.read(telegramLoginProvider.notifier);
      // Опрос без конца: PollPending по умолчанию.
      final future = notifier.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(telegramLoginProvider).phase, LoginPhase.waiting);

      notifier.cancel();
      await future.timeout(const Duration(seconds: 2));
      expect(c.read(telegramLoginProvider).phase, LoginPhase.idle);
      final calls = api.pollCalls;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(api.pollCalls, calls, reason: 'после отмены опросов больше нет');
    });

    test('повторный start во время ожидания игнорируется', () async {
      final c = container();
      final notifier = c.read(telegramLoginProvider.notifier);
      final first = notifier.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await notifier.start();
      expect(api.startCalls, 1);
      notifier.cancel();
      await first;
    });

    test('после ошибки можно начать заново', () async {
      final c = container();
      api.startResult = AuthApiException('network');
      await c.read(telegramLoginProvider.notifier).start();
      api.startResult = StartedLogin(
        requestId: 'r2',
        pollSecret: 's2',
        botUrl: Uri.parse('https://t.me/b?start=y'),
        expiresIn: const Duration(minutes: 5),
      );
      api.pollResults.add(PollSuccess(fakeSession()));
      await c.read(telegramLoginProvider.notifier).start();
      expect(c.read(telegramLoginProvider).phase, LoginPhase.success);
    });

    test('openTelegram открывает ту же ссылку ещё раз', () async {
      final c = container();
      final notifier = c.read(telegramLoginProvider.notifier);
      final future = notifier.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await notifier.openTelegram();
      expect(opened, hasLength(2));
      notifier.cancel();
      await future;
    });
  });

  group('сессия', () {
    test('при запуске читает сохранённую сессию', () async {
      final c = container(stored: fakeSession());
      expect((await c.read(authControllerProvider.future))!.user.phone, '+998901234567');
    });

    test('без сохранённой сессии — не вошли', () async {
      final c = container();
      expect(await c.read(authControllerProvider.future), isNull);
      expect(c.read(currentUserProvider), isNull);
    });

    test('действующий токен возвращается без обращения к серверу', () async {
      final c = container(stored: fakeSession());
      await c.read(authControllerProvider.future);
      expect(await c.read(authControllerProvider.notifier).validAccessToken(), 'access-1');
      expect(api.refreshCalls, 0);
    });

    test('истёкший токен обновляется и новая пара сохраняется', () async {
      final c = container(stored: fakeSession(expiresIn: const Duration(seconds: 5)));
      await c.read(authControllerProvider.future);

      final token = await c.read(authControllerProvider.notifier).validAccessToken();

      expect(token, 'access-2');
      expect(api.refreshed, ['refresh-1']);
      expect(store.session!.tokens.refreshToken, 'refresh-2');
      expect(c.read(authControllerProvider).value!.tokens.accessToken, 'access-2');
    });

    test('параллельные запросы токена вызывают одно обновление', () async {
      final c = container(stored: fakeSession(expiresIn: const Duration(seconds: 1)));
      await c.read(authControllerProvider.future);
      final notifier = c.read(authControllerProvider.notifier);

      final tokens = await Future.wait([for (var i = 0; i < 5; i++) notifier.validAccessToken()]);

      expect(api.refreshCalls, 1);
      expect(tokens.toSet(), {'access-2'});
    });

    test('сервер отозвал refresh-токен — выход из аккаунта', () async {
      final c = container(stored: fakeSession(expiresIn: Duration.zero));
      await c.read(authControllerProvider.future);
      api.refreshResults.add(AuthApiException('refresh_reused', status: 401));

      final token = await c.read(authControllerProvider.notifier).validAccessToken();

      expect(token, isNull);
      expect(c.read(authControllerProvider).value, isNull);
      expect(store.session, isNull);
    });

    test('нет связи при обновлении — сессия сохраняется, отдаётся прежний токен', () async {
      final c = container(stored: fakeSession(expiresIn: Duration.zero));
      await c.read(authControllerProvider.future);
      api.refreshResults.add(AuthApiException('network'));

      final token = await c.read(authControllerProvider.notifier).validAccessToken();

      expect(token, 'access-1');
      expect(c.read(authControllerProvider).value, isNotNull);
      expect(store.session, isNotNull);
    });

    test('ошибка сервера (5xx) при обновлении — сессия сохраняется', () async {
      final c = container(stored: fakeSession(expiresIn: Duration.zero));
      await c.read(authControllerProvider.future);
      api.refreshResults.add(AuthApiException('error', status: 503));
      await c.read(authControllerProvider.notifier).validAccessToken();
      expect(store.session, isNotNull);
    });

    test('выход: сессия на сервере закрыта, локально стёрта', () async {
      final c = container(stored: fakeSession());
      await c.read(authControllerProvider.future);

      await c.read(authControllerProvider.notifier).signOut();

      expect(api.loggedOut, ['access-1']);
      expect(store.session, isNull);
      expect(c.read(authControllerProvider).value, isNull);
    });

    test('выход без сети всё равно стирает локальную сессию', () async {
      final c = container(stored: fakeSession());
      await c.read(authControllerProvider.future);
      api.logoutResult = AuthApiException('network');

      await c.read(authControllerProvider.notifier).signOut();

      expect(store.session, isNull);
      expect(c.read(authControllerProvider).value, isNull);
    });

    test('выход, когда не входили, ничего не ломает', () async {
      final c = container();
      await c.read(authControllerProvider.future);
      await c.read(authControllerProvider.notifier).signOut();
      expect(api.loggedOut, isEmpty);
    });
  });

  group('предложение войти', () {
    final first = DateTime(2026, 1, 1);

    bool show({
      DateTime? now,
      DateTime? firstUse,
      int records = 0,
      DateTime? snoozed,
      bool signedIn = false,
      bool server = true,
      LoginPromptConfig config = const LoginPromptConfig(),
    }) =>
        shouldShowLoginPrompt(
          now: now ?? first,
          firstUse: firstUse ?? first,
          recordCount: records,
          snoozedUntil: snoozed,
          signedIn: signedIn,
          serverConfigured: server,
          config: config,
        );

    test('сразу после установки не показываем', () => expect(show(), isFalse));

    test('через 3 дня показываем', () {
      expect(show(now: first.add(const Duration(days: 2, hours: 23))), isFalse);
      expect(show(now: first.add(const Duration(days: 3))), isTrue);
      expect(show(now: first.add(const Duration(days: 30))), isTrue);
    });

    test('или после 20 записей', () {
      expect(show(records: 19), isFalse);
      expect(show(records: 20), isTrue);
      expect(show(records: 500), isTrue);
    });

    test('вошедшему не показываем никогда', () {
      expect(show(signedIn: true, records: 500, now: first.add(const Duration(days: 99))), isFalse);
    });

    test('без настроенного сервера не показываем', () {
      expect(show(server: false, records: 500), isFalse);
    });

    test('без даты первого использования (онбординг не пройден) не показываем', () {
      expect(
        shouldShowLoginPrompt(
          now: first.add(const Duration(days: 9)),
          firstUse: null,
          recordCount: 99,
          snoozedUntil: null,
          signedIn: false,
          serverConfigured: true,
        ),
        isFalse,
      );
    });

    test('отложенное предложение молчит до конца срока', () {
      final now = first.add(const Duration(days: 10));
      expect(show(now: now, snoozed: now.add(const Duration(days: 1))), isFalse);
      expect(show(now: now, snoozed: now), isTrue, reason: 'срок откладывания наступил');
      expect(show(now: now, snoozed: now.subtract(const Duration(hours: 1))), isTrue);
    });

    test('пороги настраиваются', () {
      const cfg = LoginPromptConfig(afterDays: 7, afterRecords: 5);
      expect(show(now: first.add(const Duration(days: 5)), config: cfg), isFalse);
      expect(show(now: first.add(const Duration(days: 7)), config: cfg), isTrue);
      expect(show(records: 5, config: cfg), isTrue);
      expect(show(records: 4, config: cfg), isFalse);
    });

    test('значения по умолчанию: 3 дня, 20 записей, откладывание на 3 дня', () {
      const c = LoginPromptConfig();
      expect([c.afterDays, c.afterRecords, c.snoozeDays], [3, 20, 3]);
    });
  });
}
