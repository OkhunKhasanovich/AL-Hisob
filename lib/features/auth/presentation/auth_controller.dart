import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_providers.dart';
import '../domain/auth_api.dart';
import '../domain/auth_models.dart';

/// Состояние входа: `null` — не вошли. `loading` — читаем сохранённую сессию.
class AuthController extends AsyncNotifier<AuthSession?> {
  /// Обновление токена выполняется одно на всех: параллельные запросы ждут его же.
  Future<AuthSession?>? _refreshing;

  @override
  Future<AuthSession?> build() => ref.read(tokenStoreProvider).read();

  Future<void> signIn(AuthSession session) async {
    await ref.read(tokenStoreProvider).write(session);
    state = AsyncData(session);
  }

  /// Выход: локальные данные остаются, сессия на сервере закрывается (если есть сеть).
  Future<void> signOut() async {
    final accessToken = (await validAccessToken());
    state = const AsyncData(null);
    await ref.read(tokenStoreProvider).clear();
    if (accessToken != null) {
      try {
        await ref.read(authApiProvider).logout(accessToken);
      } on AuthApiException {
        // Нет сети — сервер закроет сессию по сроку.
      }
    }
  }

  /// Действующий access-токен (при необходимости обновляет). `null` — не вошли
  /// или сессия больше недействительна (тогда пользователь выходит из аккаунта).
  /// При обрыве связи возвращает прежний токен: сервер сам решит, годится ли он.
  Future<String?> validAccessToken({Duration margin = const Duration(seconds: 30)}) async {
    final session = state.value;
    if (session == null) return null;
    if (!session.tokens.expiresWithin(margin)) return session.tokens.accessToken;

    final refreshed = await (_refreshing ??= _refresh(session).whenComplete(() => _refreshing = null));
    return refreshed?.tokens.accessToken ?? (state.value == null ? null : session.tokens.accessToken);
  }

  Future<AuthSession?> _refresh(AuthSession current) async {
    try {
      final fresh = await ref.read(authApiProvider).refresh(current.tokens.refreshToken);
      await ref.read(tokenStoreProvider).write(fresh);
      state = AsyncData(fresh);
      return fresh;
    } on AuthApiException catch (e) {
      if (e.isNetwork || e.status >= 500) return null; // временно: сессию не трогаем
      // 401/410: refresh-токен отозван или украден — входим заново.
      state = const AsyncData(null);
      await ref.read(tokenStoreProvider).clear();
      return null;
    }
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

/// Удобный доступ к пользователю.
final currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(authControllerProvider).value?.user,
);
