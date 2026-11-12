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
    this.connections = 6,
    this.blockSize = 1024 * 1024,
    this.parallelMinSize = 2 * 1024 * 1024,
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

  /// Сколько соединений качают файл одновременно. Провайдеры нередко режут скорость одного
  /// соединения (браузеры потому и качают большие файлы в несколько потоков).
  final int connections;

  /// Файл делится на блоки такого размера; свободное соединение берёт следующий блок,
  /// поэтому медленное соединение не тормозит остальные.
  final int blockSize;

  /// Файлы меньше этого размера качаются одним потоком.
  final int parallelMinSize;
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
    final target = File('${directory.path}/al-hisob-${info.build}.apk');
    final part = File('${target.path}.part');

    // Чистим старые загрузки, кроме нужной (и её недокачанной части).
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path != target.path &&
          entity.path != part.path &&
          entity.path != '${part.path}.blocks') {
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

    var parallelDone = false;
    final size = info.size;
    if (connections > 1 && size != null && size >= parallelMinSize) {
      try {
        await _downloadParallel(
          part,
          info,
          size,
          onProgress: onProgress,
          onBytes: onBytes,
          onRetry: onRetry,
          isCancelled: isCancelled,
        );
        parallelDone = true;
      } on _RangeNotSupported {
        // Сервер не умеет отдавать части: качаем одним потоком.
        await _deleteQuietly(part);
        await _deleteQuietly(File('${part.path}.blocks'));
      }
    }

    var failures = 0;
    while (!parallelDone) {
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
      await _deleteQuietly(File('${part.path}.blocks'));
      throw UpdateVerifyException('size or checksum mismatch');
    }
    await _deleteQuietly(File('${part.path}.blocks'));
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

  /// Качает файл блоками по [connections] соединений сразу, записывая каждый блок на своё место
  /// в `.part`. Какие блоки уже готовы, хранится в `.blocks`, поэтому после обрыва или
  /// перезапуска приложения докачиваются только недостающие блоки.
  Future<void> _downloadParallel(
    File part,
    UpdateInfo info,
    int size, {
    void Function(double fraction)? onProgress,
    void Function(int received, int? total)? onBytes,
    void Function(int attempt)? onRetry,
    bool Function()? isCancelled,
  }) async {
    final blocksFile = File('${part.path}.blocks');
    final blockCount = (size + blockSize - 1) ~/ blockSize;
    int blockLength(int i) => i == blockCount - 1 ? size - i * blockSize : blockSize;

    // Что уже скачано в прошлый раз (годится, только если файл нужного размера).
    final done = <int>{};
    if (await part.exists() && await part.length() == size && await blocksFile.exists()) {
      for (final v in (await blocksFile.readAsString()).split(',')) {
        final i = int.tryParse(v);
        if (i != null && i >= 0 && i < blockCount) done.add(i);
      }
    } else {
      await _deleteQuietly(part);
      await _deleteQuietly(blocksFile);
      final raf = await part.open(mode: FileMode.write);
      await raf.truncate(size);
      await raf.close();
    }

    var doneBytes = done.fold<int>(0, (sum, i) => sum + blockLength(i));
    final inFlight = <int, int>{}; // блок → сколько байт уже получено в этой попытке
    void report() {
      final received = doneBytes + inFlight.values.fold<int>(0, (a, b) => a + b);
      onProgress?.call((received / size).clamp(0.0, 1.0));
      onBytes?.call(received, size);
    }

    final pending = [for (var i = 0; i < blockCount; i++) if (!done.contains(i)) i];
    if (pending.isEmpty) return;
    report();

    final client = _clientFactory()..maxConnectionsPerHost = connections;
    try {
      // Редирект тоже может споткнуться о сеть: повторяем так же, как и блоки.
      Future<Uri> resolveWithRetries() async {
        var failures = 0;
        while (true) {
          if (isCancelled?.call() ?? false) throw UpdateCancelledException();
          try {
            return await _resolve(client, info.apkUrl);
          } on _Retryable catch (e) {
            failures++;
            if (failures >= maxAttempts) {
              throw UpdateDownloadException('gave up resolving url: ${e.reason}');
            }
            onRetry?.call(failures);
            await Future<void>.delayed(_backoff(failures));
          }
        }
      }

      var url = await resolveWithRetries();
      Future<Uri>? reresolving;
      Future<Uri> refreshUrl(Uri stale) {
        // Ссылка CDN временная: если её отозвали, заново проходим редирект (один раз для всех).
        if (url != stale) return Future.value(url);
        return reresolving ??= resolveWithRetries().then((fresh) {
          url = fresh;
          return fresh;
        }).whenComplete(() => reresolving = null);
      }

      var next = 0;
      var aborted = false;
      var chain = Future<void>.value(); // записи в .blocks — по одной

      Future<void> worker() async {
        final raf = await part.open(mode: FileMode.append);
        try {
          while (!aborted && next < pending.length) {
            if (isCancelled?.call() ?? false) throw UpdateCancelledException();
            final block = pending[next++];
            final start = block * blockSize;
            final length = blockLength(block);

            var failures = 0;
            while (true) {
              inFlight[block] = 0;
              try {
                await _fetchBlock(
                  client,
                  url,
                  raf,
                  start,
                  length,
                  isAborted: () => aborted || (isCancelled?.call() ?? false),
                  onChunk: (n) {
                    inFlight[block] = (inFlight[block] ?? 0) + n;
                    report();
                  },
                  onExpired: refreshUrl,
                  onNewUrl: (u) => url = u,
                );
                break;
              } on _Retryable catch (e) {
                inFlight.remove(block);
                failures++;
                if (failures >= maxAttempts) {
                  throw UpdateDownloadException('gave up on block $block: ${e.reason}');
                }
                onRetry?.call(failures);
                await Future<void>.delayed(_backoff(failures));
              }
            }

            inFlight.remove(block);
            done.add(block);
            doneBytes += length;
            report();
            // Список готовых блоков записываем по очереди, чтобы файл не перемешался.
            chain = chain.then((_) => blocksFile.writeAsString(done.join(',')));
          }
        } catch (_) {
          aborted = true; // остальные соединения тоже останавливаются
          rethrow;
        } finally {
          await raf.close();
        }
      }

      final results = await Future.wait(
        [for (var i = 0; i < connections && i < pending.length; i++) worker()],
        eagerError: false,
        // Ошибки соберём ниже, чтобы выбрать главную.
      ).then<Object?>((_) => null).catchError((Object e) => e);
      await chain;
      if (results != null) throw results;
    } finally {
      client.close(force: true);
    }
  }

  /// Один блок: запрос с `Range`, запись в файл по смещению. Бросает [_Retryable],
  /// если блок стоит попробовать снова, и [_RangeNotSupported], если сервер игнорирует Range.
  Future<void> _fetchBlock(
    HttpClient client,
    Uri url,
    RandomAccessFile raf,
    int start,
    int length, {
    required bool Function() isAborted,
    required void Function(int bytes) onChunk,
    required Future<Uri> Function(Uri stale) onExpired,
    required void Function(Uri fresh) onNewUrl,
  }) async {
    try {
      final request = await client.getUrl(url).timeout(stallTimeout);
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'al-hisob-updater')
        ..set(HttpHeaders.acceptEncodingHeader, 'identity')
        ..set(HttpHeaders.rangeHeader, 'bytes=$start-${start + length - 1}');
      final response = await request.close().timeout(stallTimeout);
      final status = response.statusCode;

      if (status == HttpStatus.ok) {
        // Range проигнорирован: целиком файл по частям не собрать.
        throw _RangeNotSupported();
      }
      if (status == HttpStatus.forbidden ||
          status == HttpStatus.unauthorized ||
          status == HttpStatus.gone) {
        await response.drain<void>();
        final fresh = await onExpired(url); // временная ссылка устарела
        onNewUrl(fresh);
        throw _Retryable('link expired');
      }
      if (status != HttpStatus.partialContent) {
        await response.drain<void>();
        if (status >= 500 || status == HttpStatus.tooManyRequests) throw _Retryable('HTTP $status');
        throw UpdateDownloadException('HTTP $status');
      }

      var position = start;
      var received = 0;
      await for (final chunk in response.timeout(stallTimeout)) {
        if (isAborted()) throw UpdateCancelledException();
        await raf.setPosition(position);
        await raf.writeFrom(chunk);
        position += chunk.length;
        received += chunk.length;
        onChunk(chunk.length);
      }
      if (received != length) throw _Retryable('block cut short ($received of $length)');
    } on TimeoutException {
      throw _Retryable('stalled');
    } on SocketException catch (e) {
      throw _Retryable('network: ${e.message}');
    } on HttpException catch (e) {
      throw _Retryable('http: ${e.message}');
    } on TlsException catch (e) {
      throw _Retryable('tls: ${e.message}');
    }
  }

  /// Проходит редиректы вручную (GitHub → CDN), проверяя каждый адрес, и убеждается,
  /// что итоговый сервер понимает `Range`. Возвращает адрес, с которого можно качать блоки.
  Future<Uri> _resolve(HttpClient client, Uri start) async {
    var current = start;
    for (var hop = 0; hop < 6; hop++) {
      if (!_isAllowed(current)) {
        throw UpdateDownloadException('untrusted url: ${current.host}');
      }
      try {
        final request = await client.getUrl(current).timeout(stallTimeout);
        request.followRedirects = false;
        request.headers
          ..set(HttpHeaders.userAgentHeader, 'al-hisob-updater')
          ..set(HttpHeaders.acceptEncodingHeader, 'identity')
          ..set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final response = await request.close().timeout(stallTimeout);
        final status = response.statusCode;
        final location = response.headers.value(HttpHeaders.locationHeader);

        if (status >= 300 && status < 400 && location != null) {
          await response.drain<void>();
          current = current.resolve(location);
          continue;
        }
        if (status == HttpStatus.partialContent) {
          await response.drain<void>();
          return current;
        }
        if (status == HttpStatus.ok) throw _RangeNotSupported();
        await response.drain<void>();
        if (status >= 500 || status == HttpStatus.tooManyRequests) throw _Retryable('HTTP $status');
        throw UpdateDownloadException('HTTP $status');
      } on TimeoutException {
        throw _Retryable('stalled');
      } on SocketException catch (e) {
        throw _Retryable('network: ${e.message}');
      } on HttpException catch (e) {
        throw _Retryable('http: ${e.message}');
      } on TlsException catch (e) {
        throw _Retryable('tls: ${e.message}');
      }
    }
    throw UpdateDownloadException('too many redirects');
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
        ..set(HttpHeaders.userAgentHeader, 'al-hisob-updater')
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

/// Сервер не поддерживает `Range`: блоками не скачать.
class _RangeNotSupported implements Exception {}
