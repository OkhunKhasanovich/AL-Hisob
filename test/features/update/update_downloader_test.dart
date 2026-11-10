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

  UpdateDownloader downloader() => UpdateDownloader(directory: dir, isAllowed: (_) => true);

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
}
