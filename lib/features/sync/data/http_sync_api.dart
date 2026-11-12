import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../auth/domain/auth_models.dart';
import '../domain/sync_api.dart';

/// Запросы синхронизации к API (`dart:io`, HTTPS, JSON, таймауты).
class HttpSyncApi implements SyncApi {
  HttpSyncApi({String? baseUrl, this.timeout = const Duration(seconds: 30)})
      : _base = Uri.parse(baseUrl ?? apiBaseUrl);

  final Uri _base;
  final Duration timeout;

  @override
  Future<PushResult> push(String accessToken, List<SyncChange> changes) async {
    final json = await _send(
      'POST',
      '/v1/sync/push',
      accessToken,
      body: {'changes': [for (final c in changes) c.toJson()]},
    );
    return PushResult(
      accepted: {for (final id in json['accepted']! as List) id as String},
      stale: [
        for (final c in json['stale']! as List) SyncChange.fromJson((c as Map).cast<String, Object?>()),
      ],
    );
  }

  @override
  Future<PullPage> pull(String accessToken, {required int since, int limit = 500}) async {
    final json = await _send('GET', '/v1/sync/pull', accessToken, query: {'since': '$since', 'limit': '$limit'});
    return PullPage(
      changes: [
        for (final c in json['changes']! as List) SyncChange.fromJson((c as Map).cast<String, Object?>()),
      ],
      cursor: json['cursor']! as int,
      hasMore: json['has_more']! as bool,
    );
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path,
    String accessToken, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = _base.replace(
        path: '${_base.path.replaceFirst(RegExp(r'/$'), '')}$path',
        queryParameters: query,
      );
      final request = await (method == 'POST' ? client.postUrl(uri) : client.getUrl(uri)).timeout(timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, Object?>) throw SyncApiException('bad_response', status: response.statusCode);
        return decoded;
      }
      throw SyncApiException(_errorCode(text), status: response.statusCode);
    } on TimeoutException {
      throw SyncApiException('network');
    } on SocketException {
      throw SyncApiException('network');
    } on HandshakeException {
      throw SyncApiException('network');
    } on HttpException {
      throw SyncApiException('network');
    } on FormatException {
      throw SyncApiException('bad_response', status: 200);
    } finally {
      client.close(force: true);
    }
  }

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
}
