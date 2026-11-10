import 'auth_models.dart';

/// Ошибка запроса к серверу. [status] == 0 — сервер недоступен (нет сети, таймаут).
class AuthApiException implements Exception {
  AuthApiException(this.code, {this.status = 0});

  /// Код с сервера (`expired`, `rate_limited`, `invalid_refresh`…) или `network`.
  final String code;
  final int status;

  bool get isNetwork => status == 0;

  @override
  String toString() => 'AuthApiException($code, $status)';
}

class StartedLogin {
  const StartedLogin({
    required this.requestId,
    required this.pollSecret,
    required this.botUrl,
    required this.expiresIn,
  });

  final String requestId;
  final String pollSecret;

  /// Ссылка на бота: `https://t.me/<бот>?start=<токен>`.
  final Uri botUrl;

  /// Сколько секунд запрос живёт.
  final Duration expiresIn;
}

/// Ответ опроса: либо ждём подтверждения, либо вход выполнен.
sealed class PollResult {
  const PollResult();
}

class PollPending extends PollResult {
  const PollPending();
}

class PollSuccess extends PollResult {
  const PollSuccess(this.session);

  final AuthSession session;
}

/// Запросы авторизации к серверу.
abstract interface class AuthApi {
  Future<StartedLogin> startTelegramLogin({String? deviceName});

  Future<PollResult> pollTelegramLogin({required String requestId, required String pollSecret});

  /// Меняет refresh-токен на новую пару токенов.
  Future<AuthSession> refresh(String refreshToken);

  Future<void> logout(String accessToken);
}
