import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/auth/data/http_auth_api.dart';
import 'package:al_savdogar/features/auth/domain/auth_api.dart';

import '../../helpers/local_http_server.dart';

void main() {
  late LocalHttpServer server;
  late HttpAuthApi api;
  final received = <({String path, Map<String, Object?> body, String? auth})>[];

  void serveJson(String path, int status, Object? body) {
    server.routes[path] = (response) async {
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      if (body != null) response.write(jsonEncode(body));
      await response.close();
    };
  }

  setUp(() async {
    received.clear();
    server = await LocalHttpServer.start();
    server.onRequest = (request, body) {
      received.add((
        path: request.uri.path,
        body: body.isEmpty ? {} : (jsonDecode(body) as Map).cast<String, Object?>(),
        auth: request.headers.value(HttpHeaders.authorizationHeader),
      ));
    };
    api = HttpAuthApi(baseUrl: 'http://127.0.0.1:${server.port}', timeout: const Duration(seconds: 2));
  });
  tearDown(() => server.close());

  test('start: разбирает ответ и отправляет имя устройства', () async {
    serveJson('/v1/auth/telegram/start', 200, {
      'request_id': 'r1',
      'poll_secret': 's1',
      'bot_url': 'https://t.me/Bot?start=tok',
      'expires_in': 600,
    });

    final started = await api.startTelegramLogin(deviceName: 'android');

    expect(started.requestId, 'r1');
    expect(started.pollSecret, 's1');
    expect(started.botUrl.toString(), 'https://t.me/Bot?start=tok');
    expect(started.expiresIn, const Duration(minutes: 10));
    expect(received.single.body, {'device_name': 'android'});
  });

  test('poll: pending', () async {
    serveJson('/v1/auth/telegram/poll', 200, {'status': 'pending'});
    final r = await api.pollTelegramLogin(requestId: 'r', pollSecret: 's');
    expect(r, isA<PollPending>());
    expect(received.single.body, {'request_id': 'r', 'poll_secret': 's'});
  });

  test('poll: успех → сессия с временем истечения access-токена', () async {
    serveJson('/v1/auth/telegram/poll', 200, {
      'status': 'ok',
      'access_token': 'A',
      'refresh_token': 'R',
      'expires_in': 900,
      'user': {'id': 'u1', 'phone': '+998901234567', 'name': 'Ali'},
    });

    final r = await api.pollTelegramLogin(requestId: 'r', pollSecret: 's') as PollSuccess;

    expect(r.session.user.phone, '+998901234567');
    expect(r.session.tokens.accessToken, 'A');
    expect(r.session.tokens.refreshToken, 'R');
    final seconds = r.session.tokens.accessExpiresAt.difference(DateTime.now()).inSeconds;
    expect(seconds, inInclusiveRange(880, 900));
  });

  test('refresh: отправляет токен и возвращает новую пару', () async {
    serveJson('/v1/auth/refresh', 200, {
      'access_token': 'A2',
      'refresh_token': 'R2',
      'expires_in': 900,
      'user': {'id': 'u1', 'phone': '+998901234567', 'name': null},
    });
    final s = await api.refresh('R1');
    expect(received.single.body, {'refresh_token': 'R1'});
    expect([s.tokens.accessToken, s.tokens.refreshToken], ['A2', 'R2']);
    expect(s.user.name, isNull);
  });

  test('logout: передаёт Bearer-токен, ответ 204 — успех', () async {
    server.routes['/v1/auth/logout'] = (response) async {
      response.statusCode = 204;
      await response.close();
    };
    await api.logout('ACCESS');
    expect(received.single.auth, 'Bearer ACCESS');
  });

  test('ошибки сервера превращаются в код и статус', () async {
    serveJson('/v1/auth/telegram/poll', 410, {'detail': {'code': 'expired'}});
    await expectLater(
      api.pollTelegramLogin(requestId: 'r', pollSecret: 's'),
      throwsA(isA<AuthApiException>().having((e) => e.code, 'code', 'expired').having((e) => e.status, 'status', 410)),
    );

    serveJson('/v1/auth/refresh', 401, {'detail': {'code': 'refresh_reused'}});
    await expectLater(api.refresh('x'), throwsA(isA<AuthApiException>().having((e) => e.code, 'code', 'refresh_reused')));

    serveJson('/v1/auth/telegram/start', 429, {'detail': {'code': 'rate_limited'}});
    await expectLater(api.startTelegramLogin(), throwsA(isA<AuthApiException>().having((e) => e.status, 'status', 429)));
  });

  test('не-JSON и неожиданный формат ошибки → код error', () async {
    server.routes['/v1/auth/refresh'] = (response) async {
      response.statusCode = 502;
      response.write('<html>Bad gateway</html>');
      await response.close();
    };
    await expectLater(
      api.refresh('x'),
      throwsA(isA<AuthApiException>().having((e) => e.code, 'code', 'error').having((e) => e.status, 'status', 502)),
    );

    serveJson('/v1/auth/telegram/start', 422, {'detail': [{'msg': 'bad'}]});
    await expectLater(api.startTelegramLogin(), throwsA(isA<AuthApiException>().having((e) => e.code, 'code', 'error')));
  });

  test('сервер недоступен → network (status 0)', () async {
    final dead = HttpAuthApi(baseUrl: 'http://127.0.0.1:1', timeout: const Duration(seconds: 1));
    await expectLater(
      dead.startTelegramLogin(),
      throwsA(isA<AuthApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
    );
  });

  test('зависший сервер → network по таймауту', () async {
    server.routes['/v1/auth/telegram/start'] = (response) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      await response.close();
    };
    final fast = HttpAuthApi(baseUrl: 'http://127.0.0.1:${server.port}', timeout: const Duration(milliseconds: 300));
    await expectLater(
      fast.startTelegramLogin(),
      throwsA(isA<AuthApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
    );
  });

  test('битый успешный ответ → bad_response', () async {
    server.routes['/v1/auth/telegram/start'] = (response) async {
      response.statusCode = 200;
      response.write('not json');
      await response.close();
    };
    await expectLater(api.startTelegramLogin(), throwsA(isA<AuthApiException>().having((e) => e.code, 'code', 'bad_response')));
  });

  test('базовый адрес с путём и слешем собирается корректно', () async {
    serveJson('/api/v1/auth/telegram/poll', 200, {'status': 'pending'});
    final prefixed = HttpAuthApi(baseUrl: 'http://127.0.0.1:${server.port}/api/', timeout: const Duration(seconds: 2));
    expect(await prefixed.pollTelegramLogin(requestId: 'r', pollSecret: 's'), isA<PollPending>());
  });
}
