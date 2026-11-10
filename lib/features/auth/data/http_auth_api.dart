import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/auth_api.dart';
import '../domain/auth_models.dart';

/// Запросы к API через `dart:io` (HTTPS, JSON, таймауты).
class HttpAuthApi implements AuthApi {
  HttpAuthApi({String? baseUrl, this.timeout = const Duration(seconds: 15)})
      : _base = Uri.parse(baseUrl ?? apiBaseUrl);

  final Uri _base;
  final Duration timeout;

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    String? bearer,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = _base.replace(path: '${_base.path.replaceFirst(RegExp(r'/$'), '')}$path');
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (text.isEmpty) return const {};
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, Object?>) throw AuthApiException('bad_response', status: response.statusCode);
        return decoded;
      }
      throw AuthApiException(_errorCode(text), status: response.statusCode);
    } on TimeoutException {
      throw AuthApiException('network');
    } on SocketException {
      throw AuthApiException('network');
    } on HandshakeException {
      throw AuthApiException('network');
    } on HttpException {
      throw AuthApiException('network');
    } on FormatException {
      throw AuthApiException('bad_response', status: 200);
    } finally {
      client.close(force: true);
    }
  }

  /// Код ошибки из `{"detail": {"code": "..."}}`; для прочих ответов — `error`.
  static String _errorCode(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['detail'] is Map) {
        final code = (json['detail'] as Map)['code'];
        if (code is String) return code;
      }
    } on FormatException {
      // не JSON
    }
    return 'error';
  }

  AuthSession _session(Map<String, Object?> json) {
    final user = AuthUser.fromJson((json['user']! as Map).cast<String, Object?>());
    final expiresIn = json['expires_in']! as int;
    return AuthSession(
      user: user,
      tokens: AuthTokens(
        accessToken: json['access_token']! as String,
        refreshToken: json['refresh_token']! as String,
        accessExpiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      ),
    );
  }

  @override
  Future<StartedLogin> startTelegramLogin({String? deviceName}) async {
    final json = await _post('/v1/auth/telegram/start', {'device_name': deviceName});
    return StartedLogin(
      requestId: json['request_id']! as String,
      pollSecret: json['poll_secret']! as String,
      botUrl: Uri.parse(json['bot_url']! as String),
      expiresIn: Duration(seconds: json['expires_in']! as int),
    );
  }

  @override
  Future<PollResult> pollTelegramLogin({required String requestId, required String pollSecret}) async {
    final json = await _post('/v1/auth/telegram/poll', {'request_id': requestId, 'poll_secret': pollSecret});
    if (json['status'] == 'ok') return PollSuccess(_session(json));
    return const PollPending();
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async =>
      _session(await _post('/v1/auth/refresh', {'refresh_token': refreshToken}));

  @override
  Future<void> logout(String accessToken) async {
    await _post('/v1/auth/logout', const {}, bearer: accessToken);
  }
}
