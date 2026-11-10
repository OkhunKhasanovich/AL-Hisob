import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/update_info.dart';

class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Загружает JSON; `null` — ресурса нет (404, например релизов ещё нет).
typedef JsonFetcher = Future<Map<String, Object?>?> Function(Uri uri);

/// Проверяет, есть ли в релизах GitHub версия новее установленной.
class UpdateChecker {
  UpdateChecker({
    required this.currentBuild,
    required this.abis,
    this.repository = updateRepository,
    JsonFetcher? fetch,
  }) : _fetch = fetch ?? fetchJson;

  final int currentBuild;
  final String repository;
  final Future<List<String>> Function() abis;
  final JsonFetcher _fetch;

  /// Новая версия или `null`, если установлена последняя (или проверка отключена).
  Future<UpdateInfo?> check() async {
    if (currentBuild <= 0) return null;

    final uri = Uri.https('api.github.com', '/repos/$repository/releases/latest');
    final json = await _fetch(uri);
    if (json == null) return null;

    final latest = parseLatestRelease(json, abis: await abis());
    if (latest == null) return null;
    return isUpdateAvailable(currentBuild: currentBuild, latest: latest) ? latest : null;
  }
}

/// Запрос к GitHub API без токена (лимит 60 запросов в час на IP — хватает с запасом).
Future<Map<String, Object?>?> fetchJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'al-savdogar-updater');
    final response = await request.close().timeout(const Duration(seconds: 15));

    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw UpdateCheckException('HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) throw UpdateCheckException('Unexpected response');
    return decoded;
  } on TimeoutException {
    throw UpdateCheckException('timeout');
  } on SocketException catch (e) {
    throw UpdateCheckException('network: ${e.message}');
  } on HandshakeException catch (e) {
    throw UpdateCheckException('tls: ${e.message}');
  } on FormatException catch (e) {
    throw UpdateCheckException('bad json: ${e.message}');
  } finally {
    client.close(force: true);
  }
}
