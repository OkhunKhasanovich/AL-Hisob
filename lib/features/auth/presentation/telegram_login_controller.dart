import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_providers.dart';
import '../domain/auth_api.dart';
import '../domain/auth_models.dart';
import 'auth_controller.dart';

enum LoginPhase { idle, starting, waiting, success, failed }

enum LoginFailure { network, expired, server, rateLimited, cannotOpenTelegram, botNotConfigured }

class LoginState {
  const LoginState({this.phase = LoginPhase.idle, this.failure, this.botUrl, this.user});

  final LoginPhase phase;
  final LoginFailure? failure;

  /// Ссылка на бота — чтобы открыть Telegram ещё раз.
  final Uri? botUrl;
  final AuthUser? user;
}

/// Ведёт вход: запрос на сервере → открыть бота → опрашивать, пока не подтвердят.
class TelegramLoginController extends Notifier<LoginState> {
  /// Поколение входа: устаревшие циклы опроса (после отмены/повтора) сами завершаются.
  int _generation = 0;

  static const pollInterval = Duration(seconds: 2);
  static const maxConsecutiveNetworkErrors = 5;

  @override
  LoginState build() {
    ref.onDispose(() => _generation++);
    return const LoginState();
  }

  Future<void> start() async {
    if (state.phase == LoginPhase.starting || state.phase == LoginPhase.waiting) return;
    final generation = ++_generation;
    state = const LoginState(phase: LoginPhase.starting);

    final api = ref.read(authApiProvider);
    final StartedLogin started;
    try {
      started = await api.startTelegramLogin(deviceName: Platform.operatingSystem);
    } on AuthApiException catch (e) {
      if (generation != _generation) return;
      state = LoginState(phase: LoginPhase.failed, failure: _failureOf(e));
      return;
    }
    if (generation != _generation) return;

    state = LoginState(phase: LoginPhase.waiting, botUrl: started.botUrl);
    await openTelegram();
    if (generation != _generation) return;
    await _poll(started, generation);
  }

  /// Открыть бота (повторно, если окно закрыли). Неудача не прерывает ожидание.
  Future<void> openTelegram() async {
    final url = state.botUrl;
    if (url == null) return;
    final opened = await ref.read(urlOpenerProvider)(url);
    if (!opened && state.phase == LoginPhase.waiting) {
      state = LoginState(
        phase: LoginPhase.waiting,
        botUrl: url,
        failure: LoginFailure.cannotOpenTelegram,
      );
    }
  }

  Future<void> _poll(StartedLogin started, int generation) async {
    final api = ref.read(authApiProvider);
    final delay = ref.read(loginPollDelayProvider);
    final deadline = DateTime.now().add(started.expiresIn);
    var networkErrors = 0;

    while (generation == _generation) {
      await delay(pollInterval);
      if (generation != _generation) return;
      if (DateTime.now().isAfter(deadline)) {
        state = const LoginState(phase: LoginPhase.failed, failure: LoginFailure.expired);
        return;
      }

      try {
        final result = await api.pollTelegramLogin(
          requestId: started.requestId,
          pollSecret: started.pollSecret,
        );
        networkErrors = 0;
        if (generation != _generation) return;
        if (result is PollSuccess) {
          await ref.read(authControllerProvider.notifier).signIn(result.session);
          if (generation != _generation) return;
          state = LoginState(phase: LoginPhase.success, user: result.session.user);
          return;
        }
      } on AuthApiException catch (e) {
        if (generation != _generation) return;
        if (e.isNetwork || e.status >= 500) {
          // Короткий обрыв связи не должен прерывать вход.
          if (++networkErrors >= maxConsecutiveNetworkErrors) {
            state = const LoginState(phase: LoginPhase.failed, failure: LoginFailure.network);
            return;
          }
          continue;
        }
        state = LoginState(phase: LoginPhase.failed, failure: _failureOf(e));
        return;
      }
    }
  }

  /// Прервать ожидание.
  void cancel() {
    _generation++;
    if (ref.mounted) state = const LoginState();
  }

  /// Сбросить результат (после показа ошибки/успеха).
  void reset() {
    _generation++;
    if (ref.mounted) state = const LoginState();
  }

  static LoginFailure _failureOf(AuthApiException e) {
    if (e.isNetwork) return LoginFailure.network;
    return switch (e.code) {
      'expired' || 'already_used' || 'invalid_request' => LoginFailure.expired,
      'rate_limited' => LoginFailure.rateLimited,
      'bot_not_configured' => LoginFailure.botNotConfigured,
      _ => LoginFailure.server,
    };
  }
}

final telegramLoginProvider =
    NotifierProvider<TelegramLoginController, LoginState>(TelegramLoginController.new);
