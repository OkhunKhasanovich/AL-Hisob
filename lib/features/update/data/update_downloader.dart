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

/// Скачивает APK в [directory], проверяет размер и SHA-256.
/// Уже скачанный и проверенный файл повторно не качается.
class UpdateDownloader {
  UpdateDownloader({
    required this.directory,
    bool Function(Uri)? isAllowed,
  }) : _isAllowed = isAllowed ?? isTrustedUpdateHost;

  final Directory directory;
  final bool Function(Uri) _isAllowed;

  Future<File> download(UpdateInfo info, {void Function(double fraction)? onProgress}) async {
    if (!_isAllowed(info.apkUrl)) {
      throw UpdateDownloadException('untrusted url: ${info.apkUrl.host}');
    }
    await directory.create(recursive: true);
    final target = File('${directory.path}/al-savdogar-${info.build}.apk');

    // Чистим старые загрузки, кроме нужной.
    await for (final entity in directory.list()) {
      if (entity is File && entity.path != target.path) {
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

    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(info.apkUrl);
      request.headers.set(HttpHeaders.userAgentHeader, 'al-savdogar-updater');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw UpdateDownloadException('HTTP ${response.statusCode}');
      }

      final total = response.contentLength > 0 ? response.contentLength : info.size;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) onProgress?.call((received / total).clamp(0, 1));
        }
      } finally {
        await sink.close();
      }

      if (!await _verify(part, info)) {
        await part.delete();
        throw UpdateVerifyException('size or checksum mismatch');
      }
      await part.rename(target.path);
      onProgress?.call(1);
      return target;
    } on TimeoutException {
      await _deleteQuietly(part);
      throw UpdateDownloadException('timeout');
    } on SocketException catch (e) {
      await _deleteQuietly(part);
      throw UpdateDownloadException('network: ${e.message}');
    } on UpdateDownloadException {
      await _deleteQuietly(part);
      rethrow;
    } finally {
      client.close(force: true);
    }
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
