import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/update/data/update_downloader.dart';
import 'package:al_savdogar/features/update/domain/update_info.dart';

import '../../helpers/local_http_server.dart';

void main() {
  late Directory dir;
  late LocalHttpServer server;
  late Uint8List bytes;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('updates_test');
    server = await LocalHttpServer.start();
    bytes = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    server.serveBytes('/app.apk', bytes);
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  UpdateInfo info({int build = 7, String path = '/app.apk', int? size, String? sha}) => UpdateInfo(
        build: build,
        versionName: '0.1.0',
        apkUrl: server.url(path),
        assetName: 'al-savdogar-arm64-v8a.apk',
        size: size ?? bytes.length,
        sha256: sha ?? sha256.convert(bytes).toString(),
      );

  UpdateDownloader downloader({int maxAttempts = 5, Duration stall = const Duration(seconds: 5)}) =>
      UpdateDownloader(
        directory: dir,
        isAllowed: (_) => true,
        maxAttempts: maxAttempts,
        stallTimeout: stall,
        retryDelay: Duration.zero,
      );

  test('скачивает, проверяет и отдаёт файл; прогресс растёт до 1', () async {
    final progress = <double>[];
    final file = await downloader().download(info(), onProgress: progress.add);

    expect(await file.readAsBytes(), bytes);
    expect(file.path, endsWith('al-savdogar-7.apk'));
    expect(progress.last, 1);
    expect(progress, orderedEquals([...progress]..sort()), reason: 'прогресс не убывает');
    expect(progress.every((p) => p >= 0 && p <= 1), isTrue);
  });

  test('без размера и суммы (GitHub не отдал digest) тоже работает', () async {
    final i = UpdateInfo(
        build: 1,
        versionName: 'x',
        apkUrl: server.url('/app.apk'),
        assetName: 'a.apk');
    final file = await downloader().download(i);
    expect(await file.length(), bytes.length);
  });

  test('повторный вызов использует уже скачанный файл без сети', () async {
    await downloader().download(info());
    final before = server.requests.length;

    final again = await downloader().download(info());

    expect(server.requests.length, before, reason: 'второго запроса быть не должно');
    expect(await again.length(), bytes.length);
  });

  test('битый кэшированный файл скачивается заново', () async {
    final first = await downloader().download(info());
    await first.writeAsBytes([1, 2, 3]);

    final again = await downloader().download(info());

    expect(await again.readAsBytes(), bytes);
  });

  test('неверная контрольная сумма: ошибка проверки, файлов не остаётся', () async {
    final bad = info(sha: 'a' * 64);
    await expectLater(downloader().download(bad), throwsA(isA<UpdateVerifyException>()));
    expect(await dir.list().toList(), isEmpty);
  });

  test('неверный размер: ошибка проверки', () async {
    await expectLater(
      downloader().download(info(size: bytes.length + 1)),
      throwsA(isA<UpdateVerifyException>()),
    );
    expect(await dir.list().toList(), isEmpty);
  });

  test('HTTP 404 — ошибка загрузки', () async {
    await expectLater(
      downloader().download(info(path: '/missing.apk')),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(await dir.list().toList(), isEmpty);
  });

  test('редирект (как у GitHub → CDN) обрабатывается', () async {
    server.redirect('/old.apk', '/app.apk');
    final file = await downloader().download(info(path: '/old.apk'));
    expect(await file.readAsBytes(), bytes);
  });

  test('старые загрузки удаляются', () async {
    await File('${dir.path}/al-savdogar-3.apk').writeAsBytes([1]);
    await File('${dir.path}/garbage.part').writeAsBytes([1]);

    await downloader().download(info(build: 7));

    final names = (await dir.list().toList()).map((e) => e.uri.pathSegments.last).toList();
    expect(names, ['al-savdogar-7.apk']);
  });

  test('недоверенный адрес отклоняется ещё до запроса', () async {
    final strict = UpdateDownloader(directory: dir); // проверка по умолчанию: только GitHub
    await expectLater(strict.download(info()), throwsA(isA<UpdateDownloadException>()));
    expect(server.requests, isEmpty);
  });

  test('сервер недоступен — ошибка загрузки, а не зависание', () async {
    final i = info();
    await server.close();
    await expectLater(downloader().download(i), throwsA(isA<UpdateDownloadException>()));
    // tearDown закрывает уже закрытый сервер — это допустимо
    server = await LocalHttpServer.start();
  });

  group('докачка и устойчивость к обрывам', () {
    /// Отдаёт [bytes] с поддержкой Range. Поведение первой попытки задаёт [firstAttempt]:
    /// `cut` — оборвать соединение на середине, `stall` — замолчать на середине.
    void serveFlaky(String path, {String? firstAttempt, bool supportRange = true}) {
      var attempt = 0;
      server.requestRoutes[path] = (request) async {
        attempt++;
        final response = request.response;
        final range = request.headers.value(HttpHeaders.rangeHeader);
        var start = 0;
        if (range != null && supportRange) {
          start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          if (start >= bytes.length) {
            response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            await response.close();
            return;
          }
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
              HttpHeaders.contentRangeHeader, 'bytes $start-${bytes.length - 1}/${bytes.length}');
        }
        final body = bytes.sublist(start);
        response.contentLength = body.length;
        if (attempt == 1 && firstAttempt != null) {
          if (firstAttempt == 'cut') {
            await _cutAfterHalf(response, body);
          } else {
            // 'stall': половина данных, дальше тишина — ответ не закрываем.
            response.add(body.sublist(0, body.length ~/ 2));
            await response.flush();
          }
          return;
        }
        response.add(body);
        await response.close();
      };
    }

    test('обрыв посреди загрузки: докачивает с того же места, а не заново', () async {
      serveFlaky('/flaky.apk', firstAttempt: 'cut');
      final progress = <double>[];
      var retries = 0;

      final file = await downloader().download(
        info(path: '/flaky.apk'),
        onProgress: progress.add,
        onRetry: (_) => retries++,
      );

      expect(await file.readAsBytes(), bytes);
      expect(retries, 1);
      expect(server.rangeHeaders.first, isNull);
      expect(server.rangeHeaders.last, startsWith('bytes='));
      final resumedFrom = int.parse(server.rangeHeaders.last!.substring(6, server.rangeHeaders.last!.length - 1));
      expect(resumedFrom, greaterThan(0));
      expect(progress, orderedEquals([...progress]..sort()), reason: 'прогресс не откатывается назад');
    });

    test('зависание (данные перестали идти): по таймауту докачивает', () async {
      serveFlaky('/stall.apk', firstAttempt: 'stall');
      final file = await downloader(stall: const Duration(milliseconds: 400))
          .download(info(path: '/stall.apk'));
      expect(await file.readAsBytes(), bytes);
      expect(server.rangeHeaders.length, 2);
    });

    test('остаток от прошлого запуска (.part) продолжается с его размера', () async {
      serveFlaky('/resume.apk');
      await File('${dir.path}/al-savdogar-7.apk.part').writeAsBytes(bytes.sublist(0, 1000));

      final file = await downloader().download(info(path: '/resume.apk'));

      expect(await file.readAsBytes(), bytes);
      expect(server.rangeHeaders, ['bytes=1000-']);
    });

    test('сервер не умеет Range (200 вместо 206): качаем сначала, файл целый', () async {
      serveFlaky('/norange.apk', supportRange: false);
      await File('${dir.path}/al-savdogar-7.apk.part').writeAsBytes(bytes.sublist(0, 1000));

      final file = await downloader().download(info(path: '/norange.apk'));

      expect(await file.readAsBytes(), bytes);
    });

    test('мусорный .part больше файла отбрасывается', () async {
      serveFlaky('/big.apk');
      await File('${dir.path}/al-savdogar-7.apk.part').writeAsBytes(List.filled(bytes.length + 10, 1));

      final file = await downloader().download(info(path: '/big.apk'));

      expect(await file.readAsBytes(), bytes);
      expect(server.rangeHeaders, [null]);
    });

    test('503 от сервера: повторяет и справляется', () async {
      var calls = 0;
      server.requestRoutes['/busy.apk'] = (request) async {
        calls++;
        if (calls == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      };
      final file = await downloader().download(info(path: '/busy.apk'));
      expect(await file.readAsBytes(), bytes);
      expect(calls, 2);
    });

    test('постоянные обрывы: сдаётся после maxAttempts, недокачанное остаётся для следующей попытки',
        () async {
      server.requestRoutes['/dead.apk'] = (request) async {
        await _cutAfterHalf(request.response, bytes.sublist(0, 20));
      };
      var retries = 0;
      await expectLater(
        downloader(maxAttempts: 3).download(info(path: '/dead.apk'), onRetry: (_) => retries++),
        throwsA(isA<UpdateDownloadException>()),
      );
      expect(retries, lessThanOrEqualTo(3));
      expect(File('${dir.path}/al-savdogar-7.apk.part').existsSync(), isTrue);
    });

    test('Отмена: UpdateCancelledException, недокачанное сохраняется', () async {
      // Отдаём по кусочкам, чтобы между ними успела сработать отмена.
      server.requestRoutes['/cancel.apk'] = (request) async {
        request.response.contentLength = bytes.length;
        for (var i = 0; i < bytes.length; i += 30000) {
          request.response.add(bytes.sublist(i, i + 30000 > bytes.length ? bytes.length : i + 30000));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
        await request.response.close();
      };
      var chunks = 0;
      await expectLater(
        downloader().download(
          info(path: '/cancel.apk'),
          onBytes: (_, _) => chunks++,
          isCancelled: () => chunks >= 1,
        ),
        throwsA(isA<UpdateCancelledException>()),
      );
    });

    test('404 не повторяется', () async {
      await expectLater(
        downloader().download(info(path: '/nothing.apk')),
        throwsA(isA<UpdateDownloadException>()),
      );
      expect(server.requests.where((p) => p == '/nothing.apk').length, 1);
    });

    test('onBytes сообщает полученное и общий размер', () async {
      final seen = <(int, int?)>[];
      await downloader().download(info(), onBytes: (r, t) => seen.add((r, t)));
      expect(seen.last, (bytes.length, bytes.length));
    });
  });
}

/// Обещает [body] целиком, отдаёт половину и рвёт соединение — как пропавшая сеть.
Future<void> _cutAfterHalf(HttpResponse response, List<int> body) async {
  final socket = await response.detachSocket(writeHeaders: false);
  socket.add(ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\n\r\n'));
  socket.add(body.sublist(0, body.length ~/ 2));
  await socket.flush();
  socket.destroy();
}
