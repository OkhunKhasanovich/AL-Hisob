import 'dart:collection';

import 'package:al_savdogar/features/auth/data/token_store.dart';
import 'package:al_savdogar/features/auth/domain/auth_api.dart';
import 'package:al_savdogar/features/auth/domain/auth_models.dart';

class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this.session]);

  AuthSession? session;
  int writes = 0;
  int clears = 0;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession s) async {
    writes++;
    session = s;
  }

  @override
  Future<void> clear() async {
    clears++;
    session = null;
  }
}

AuthSession fakeSession({
  String phone = '+998901234567',
  String access = 'access-1',
  String refresh = 'refresh-1',
  Duration expiresIn = const Duration(minutes: 15),
}) =>
    AuthSession(
      user: AuthUser(id: 'user-1', phone: phone, name: 'Ali'),
      tokens: AuthTokens(
        accessToken: access,
        refreshToken: refresh,
        accessExpiresAt: DateTime.now().add(expiresIn),
      ),
    );

/// Сервер авторизации для тестов: ответы задаются очередями.
class FakeAuthApi implements AuthApi {
  /// Что вернёт startTelegramLogin (или исключение).
  Object startResult = StartedLogin(
    requestId: 'req-1',
    pollSecret: 'secret-1',
    botUrl: Uri.parse('https://t.me/TestBot?start=abc'),
    expiresIn: const Duration(minutes: 10),
  );

  /// Ответы на poll по очереди; когда очередь пуста — `PollPending`.
  final Queue<Object> pollResults = Queue();

  /// Ответы на refresh по очереди; пусто — новая пара токенов.
  final Queue<Object> refreshResults = Queue();

  Object? logoutResult;

  int startCalls = 0;
  int pollCalls = 0;
  int refreshCalls = 0;
  final loggedOut = <String>[];
  final refreshed = <String>[];

  @override
  Future<StartedLogin> startTelegramLogin({String? deviceName}) async {
    startCalls++;
    final r = startResult;
    if (r is Exception) throw r;
    return r as StartedLogin;
  }

  @override
  Future<PollResult> pollTelegramLogin({required String requestId, required String pollSecret}) async {
    pollCalls++;
    if (pollResults.isEmpty) return const PollPending();
    final r = pollResults.removeFirst();
    if (r is Exception) throw r;
    return r as PollResult;
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    refreshCalls++;
    refreshed.add(refreshToken);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (refreshResults.isEmpty) {
      return fakeSession(access: 'access-${refreshCalls + 1}', refresh: 'refresh-${refreshCalls + 1}');
    }
    final r = refreshResults.removeFirst();
    if (r is Exception) throw r;
    return r as AuthSession;
  }

  @override
  Future<void> logout(String accessToken) async {
    loggedOut.add(accessToken);
    final r = logoutResult;
    if (r is Exception) throw r;
  }
}
