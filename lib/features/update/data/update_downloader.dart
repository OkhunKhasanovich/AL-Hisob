import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/update_info.dart';

class UpdateDownloadException implements Exception {
  UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => 'UpdateDownloadException: $message';
}

/// Файл скачан, но не совпал по размеру или контрольной сумме.
class UpdateVerifyException extends UpdateDownloadException {
  UpdateVerifyException(super.message);
}

/// Загрузку отменил пользователь.
class UpdateCancelledException implements Exception {}

/// Скачивает APK в [directory], проверяет размер и SHA-256.
///
/// Загрузка **докачивается**: недокачанный `.part` остаётся на диске, и после обрыва или
/// зависания соединения запрос повторяется с заголовком `Range` с того места, где остановились.
/// Так нестабильная сеть или уход приложения в фон (Android притормаживает сеть) не заставляют
/// начинать 23 МБ заново. Зависшим считается поток, из которого не приходит данных
/// дольше [stallTimeout].
/// Уже скачанный и проверенный файл повторно не качается.
class UpdateDownloader {
  UpdateDownloader({
    required this.directory,
    bool Function(Uri)? isAllowed,
    this.maxAttempts = 12,
    this.stallTimeout = const Duration(seconds: 20),
    this.retryDelay = const Duration(seconds: 2),
    HttpClient Function()? clientFactory,
  })  : _isAllowed = isAllowed ?? isTrustedUpdateHost,
        _clientFactory = clientFactory ?? _defaultClient;

  final Directory directory;
  final bool Function(Uri) _isAllowed;

  /// Сколько раз пробуем подряд, прежде чем сдаться (прогресс сбрасывает счётчик).
  final int maxAttempts;
  final Duration stallTimeout;

  /// Пауза перед повтором; растёт с каждой неудачной попыткой, но не больше 8 секунд.
  final Duration retryDelay;
  final HttpClient Function() _clientFactory;

  static HttpClient _defaultClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    // Сжатие для APK не нужно, а «живой» распаковщик мешает считать байты.
    ..autoUncompress = false;

  /// [onProgress] — доля 0…1. [onBytes] — сколько байт получено и сколько всего.
  /// [onRetry] вызывается перед повторной попыткой (с её номером, начиная с 1).
  /// [isCancelled] проверяется между кусками данных.
  Future<File> download(
    UpdateInfo info, {
    void Function(double fraction)? onProgress,
    void Function(int received, int? total)? onBytes,
    void Function(int attempt)? onRetry,
    bool Function()? isCancelled,
  }) async {
    if (!_isAllowed(info.apkUrl)) {
      throw UpdateDownloadException('untrusted url: ${info.apkUrl.host}');
    }
    await directory.create(recursive: true);
    final target = File('${directory.path}/al-savdogar-${info.build}.apk');
    final part = File('${target.path}.part');

    // Чистим старые загрузки, кроме нужной (и её недокачанной части).
    await for (final entity in directory.list()) {
      if (entity is File && entity.path != target.path && entity.path != part.path) {
        try {
          await entity.delete();
        } on FileSystemException {
          // не страшно
        }
      }
    }

    if (await target.exists()) {
      if (await _verify(target, info)) {
        onProgress?.call(1);
        return target;
      }
      await target.delete();
    }

    var failures = 0;
    while (true) {
      if (isCancelled?.call() ?? false) {
        throw UpdateCancelledException();
      }
      final before = await _length(part);
      try {
        await _fetchInto(part, info, onProgress: onProgress, onBytes: onBytes, isCancelled: isCancelled);
        break;
      } on _Retryable catch (e) {
        // Если за попытку что-то докачалось — это не «подряд неудачи».
        failures = (await _length(part)) > before ? 1 : failures + 1;
        if (failures >= maxAttempts) {
          throw UpdateDownloadException('gave up after $failures attempts: ${e.reason}');
        }
        onRetry?.call(failures);
        await Future<void>.delayed(_backoff(failures));
      }
    }

    if (!await _verify(part, info)) {
      await _deleteQuietly(part);
      throw UpdateVerifyException('size or checksum mismatch');
    }
    await part.rename(target.path);
    onProgress?.call(1);
    return target;
  }

  Duration _backoff(int failures) {
    final factor = failures < 4 ? failures : 4;
    final delay = retryDelay * factor;
    const cap = Duration(seconds: 8);
    return delay > cap ? cap : delay;
  }

  Future<int> _length(File file) async => await file.exists() ? await file.length() : 0;

  /// Одна попытка: дописывает данные в [part], начиная с его текущего размера.
  /// Бросает [_Retryable], если стоит повторить; остальные ошибки — окончательные.
  Future<void> _fetchInto(
    File part,
    UpdateInfo info, {
    void Function(double fraction)? onProgress,
    void Function(int received, int? total)? onBytes,
    bool Function()? isCancelled,
  }) async {
    var offset = await _length(part);
    final expected = info.size;
    if (expected != null && offset > expected) {
      await part.delete(); // чужой или битый хвост
      offset = 0;
    }
    if (expected != null && offset == expected) return; // всё уже есть, дальше — проверка

    final client = _clientFactory();
    try {
      final request = await client.getUrl(info.apkUrl).timeout(stallTimeout);
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'al-savdogar-updater')
        ..set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      final response = await request.close().timeout(stallTimeout);

      final status = response.statusCode;
      if (status == HttpStatus.requestedRangeNotSatisfiable) {
        await response.drain<void>();
        await _deleteQuietly(part); // хвост не подходит: начнём заново
        throw _Retryable('range not satisfiable');
      }
      if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
        await response.drain<void>();
        if (status >= 500 || status == HttpStatus.tooManyRequests) {
          throw _Retryable('HTTP $status');
        }
        throw UpdateDownloadException('HTTP $status');
      }

      // 200 на запрос с Range — сервер докачку не поддерживает: пишем сначала.
      final resumed = status == HttpStatus.partialContent && offset > 0;
      if (!resumed) offset = 0;
      final total = _totalSize(response, offset, info);
      var received = offset;

      final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in response.timeout(stallTimeout)) {
          if (isCancelled?.call() ?? false) throw UpdateCancelledException();
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
          onBytes?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (total != null && received < total) throw _Retryable('connection closed early');
    } on TimeoutException {
      throw _Retryable('stalled');
    } on SocketException catch (e) {
      throw _Retryable('network: ${e.message}');
    } on HttpException catch (e) {
      throw _Retryable('http: ${e.message}');
    } on TlsException catch (e) {
      throw _Retryable('tls: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// Полный размер файла: из `Content-Range`, длины ответа или описания релиза.
  int? _totalSize(HttpClientResponse response, int offset, UpdateInfo info) {
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    final fromRange = range == null ? null : int.tryParse(range.split('/').last);
    if (fromRange != null) return fromRange;
    if (response.contentLength > 0) return offset + response.contentLength;
    return info.size;
  }

  Future<bool> _verify(File file, UpdateInfo info) async {
    final expectedSize = info.size;
    if (expectedSize != null && await file.length() != expectedSize) return false;
    final expectedHash = info.sha256;
    if (expectedHash != null) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != expectedHash) return false;
    }
    return true;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // не страшно
    }
  }
}

/// Сбой, после которого стоит попробовать ещё раз (обрыв, зависание, 5xx).
class _Retryable implements Exception {
  _Retryable(this.reason);
  final String reason;
}
