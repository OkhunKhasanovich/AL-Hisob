import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/features/update/data/update_checker.dart';
import 'package:al_savdogar/features/update/data/update_downloader.dart';
import 'package:al_savdogar/features/update/domain/apk_installer.dart';
import 'package:al_savdogar/features/update/domain/update_info.dart';
import 'package:al_savdogar/features/update/presentation/update_controller.dart';

import '../../helpers/fake_apk_installer.dart';
import '../../helpers/local_http_server.dart';
import 'update_info_test.dart' show release, asset;

/// Разбор релиза — настоящий (доверенный github.com), а скачивание идёт на локальный
/// сервер: адрес подменяется уже после разбора.
class _RedirectingChecker extends UpdateChecker {
  _RedirectingChecker({
    required super.currentBuild,
    required super.abis,
    required super.fetch,
    required this.target,
  }) : super(repository: 'o/r');

  final Uri target;

  @override
  Future<UpdateInfo?> check() async {
    final info = await super.check();
    if (info == null) return null;
    return UpdateInfo(
      build: info.build,
      versionName: info.versionName,
      apkUrl: target,
      assetName: info.assetName,
      notes: info.notes,
      size: info.size,
      sha256: info.sha256,
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late LocalHttpServer server;
  late Uint8List apk;
  late FakeApkInstaller installer;
  late int fetchCalls;
  late Map<String, Object?>? latest;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('upd_ctrl');
    server = await LocalHttpServer.start();
    apk = Uint8List.fromList(List.generate(50000, (i) => (i * 7) % 256));
    server.serveBytes('/apk', apk);
    installer = FakeApkInstaller();
    fetchCalls = 0;
    latest = null;
  });

  tearDown(() async {
    container.dispose();
    await server.close();
    await dir.delete(recursive: true);
    await db.close();
  });

  /// Релиз build-[build] со ссылкой на локальный сервер.
  Map<String, Object?> releaseOnServer(int build, {String? sha, int? size}) => release(
        tag: 'build-$build',
        name: 'Al-Savdogar 0.2.0 ($build)',
        assets: [
          asset(
            'al-savdogar-arm64-v8a.apk',
            size: size ?? apk.length,
            digest: 'sha256:${sha ?? sha256.convert(apk)}',
            url: 'https://github.com/o/r/releases/download/build-$build/al-savdogar-arm64-v8a.apk',
          ),
        ],
      );

  ProviderContainer makeContainer({int build = 5}) {
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      currentBuildProvider.overrideWithValue(build),
      apkInstallerProvider.overrideWithValue(installer),
      updateCheckerProvider.overrideWithValue(_RedirectingChecker(
        currentBuild: build,
        abis: installer.supportedAbis,
        target: server.url('/apk'),
        fetch: (_) async {
          fetchCalls++;
          final l = latest;
          if (l == null) throw UpdateCheckException('network');
          return l;
        },
      )),
      updateDownloaderProvider.overrideWithValue(
        () async => UpdateDownloader(directory: dir, isAllowed: (_) => true),
      ),
    ]);
    return container;
  }

  UpdateState state() => container.read(updateControllerProvider);
  UpdateController controller() => container.read(updateControllerProvider.notifier);

  group('проверка', () {
    test('новая версия → available с описанием', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();

      expect(state().phase, UpdatePhase.available);
      expect(state().info!.build, 9);
      expect(state().info!.versionName, '0.2.0');
    });

    test('версия та же → upToDate', () async {
      latest = releaseOnServer(5);
      makeContainer();
      await controller().check();
      expect(state().phase, UpdatePhase.upToDate);
    });

    test('ручная проверка: ошибка сети видна пользователю', () async {
      latest = null;
      makeContainer();
      await controller().check();
      expect(state().phase, UpdatePhase.error);
      expect(state().errorKind, UpdateErrorKind.check);
    });

    test('сборка для разработки: ничего не делает', () async {
      latest = releaseOnServer(99);
      makeContainer(build: 0);
      await controller().check();
      await controller().checkOnStartup();
      expect(state().phase, UpdatePhase.idle);
      expect(fetchCalls, 0);
    });

    test('во время проверки повторный запуск игнорируется', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await Future.wait([controller().check(), controller().check()]);
      expect(fetchCalls, 1);
    });
  });

  group('проверка при запуске', () {
    test('находит обновление', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().checkOnStartup();
      expect(state().phase, UpdatePhase.available);
    });

    test('не чаще раза в 6 часов', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().checkOnStartup();
      expect(fetchCalls, 1);

      container.dispose();
      makeContainer();
      await controller().checkOnStartup();
      expect(fetchCalls, 1, reason: 'второй запуск сразу после первого — без запроса');
      expect(state().phase, UpdatePhase.idle);
    });

    test('через 6+ часов проверяет снова', () async {
      latest = releaseOnServer(9);
      makeContainer();
      final prefs = container.read(updatePrefsProvider);
      await prefs.setLastCheck(DateTime.now().subtract(const Duration(hours: 7)));

      await controller().checkOnStartup();
      expect(fetchCalls, 1);
    });

    test('ошибка сети при запуске не беспокоит пользователя', () async {
      latest = null;
      makeContainer();
      await controller().checkOnStartup();
      expect(state().phase, UpdatePhase.idle);
    });

    test('«Пропустить версию»: при запуске молчит, ручная проверка всё равно покажет', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();
      await controller().skip();
      expect(state().phase, UpdatePhase.idle);

      await container
          .read(updatePrefsProvider)
          .setLastCheck(DateTime.now().subtract(const Duration(days: 1)));
      await controller().checkOnStartup();
      expect(state().phase, UpdatePhase.idle, reason: 'пропущенная версия не показывается');

      await controller().check();
      expect(state().phase, UpdatePhase.available, reason: 'ручная проверка игнорирует пропуск');
    });

    test('следующая, более новая версия после пропуска показывается', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();
      await controller().skip();

      latest = releaseOnServer(10);
      await container
          .read(updatePrefsProvider)
          .setLastCheck(DateTime.now().subtract(const Duration(days: 1)));
      await controller().checkOnStartup();
      expect(state().phase, UpdatePhase.available);
      expect(state().info!.build, 10);
    });
  });

  group('установка', () {
    test('download(): качает без установки и переходит в ready с путём к файлу', () async {
      latest = releaseOnServer(9);
      makeContainer();
      final phases = <UpdatePhase>[];
      container.listen(updateControllerProvider, (_, next) => phases.add(next.phase));
      await controller().check();
      await controller().download();

      expect(installer.installed, isEmpty, reason: 'установка — только по согласию');
      expect(state().phase, UpdatePhase.ready);
      expect(phases, containsAllInOrder([UpdatePhase.downloading, UpdatePhase.ready]));
      expect(await File(state().apkPath!).readAsBytes(), apk);
    });

    test('ready → install() ставит скачанный файл, не качая заново', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();
      await controller().download();
      final path = state().apkPath!;

      var downloadingAgain = false;
      container.listen(updateControllerProvider, (_, next) {
        if (next.phase == UpdatePhase.downloading) downloadingAgain = true;
      });
      await controller().install();

      expect(installer.installed, [path]);
      expect(downloadingAgain, isFalse);
      expect(state().phase, UpdatePhase.idle);
    });

    test('в ready проверка и «Позже» ничего не сбрасывают', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();
      await controller().download();

      await controller().check();
      controller().dismiss();
      expect(state().phase, UpdatePhase.ready);
      expect(state().apkPath, isNotNull);
    });

    test('ошибка загрузки: повторный download() качает заново', () async {
      latest = releaseOnServer(9, sha: 'f' * 64);
      makeContainer();
      await controller().check();
      await controller().download();
      expect(state().phase, UpdatePhase.error);
      expect(state().errorKind, UpdateErrorKind.verify);
      expect(state().apkPath, isNull);
    });

    test('скачивает, проверяет и запускает установку', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();
      await controller().install();

      expect(installer.installed, hasLength(1));
      expect(installer.installed.single, endsWith('al-savdogar-9.apk'));
      expect(await File(installer.installed.single).readAsBytes(), apk);
      expect(state().phase, UpdatePhase.idle);
    });

    test('прогресс скачивания доходит до 100%', () async {
      latest = releaseOnServer(9);
      makeContainer();
      final seen = <double>[];
      container.listen(updateControllerProvider, (_, next) {
        if (next.phase == UpdatePhase.downloading) seen.add(next.progress);
      });
      await controller().check();
      await controller().install();
      expect(seen, isNotEmpty);
      expect(seen.last, 1);
    });

    test('нет разрешения на установку → needsPermission; после выдачи установка идёт без повторной загрузки', () async {
      installer.status = InstallStatus.needsPermission;
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();
      await controller().install();
      expect(state().phase, UpdatePhase.needsPermission);
      final downloads = server.requests.length;

      await controller().openInstallSettings();
      expect(installer.settingsOpened, 1);

      installer.status = InstallStatus.started;
      await controller().install();
      expect(state().phase, UpdatePhase.idle);
      expect(installer.installed, hasLength(2));
      expect(server.requests.length, downloads, reason: 'файл взят из кэша');
    });

    test('установщик не запустился → ошибка install', () async {
      installer.status = InstallStatus.failed;
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();
      await controller().install();
      expect(state().phase, UpdatePhase.error);
      expect(state().errorKind, UpdateErrorKind.install);
    });

    test('повреждённый файл → ошибка verify, установка не запускается', () async {
      latest = releaseOnServer(9, sha: 'b' * 64);
      makeContainer();
      await controller().check();
      await controller().install();
      expect(state().errorKind, UpdateErrorKind.verify);
      expect(installer.installed, isEmpty);
    });

    test('сервер недоступен → ошибка download, можно повторить', () async {
      latest = releaseOnServer(9);
      makeContainer();
      await controller().check();
      server.routes.remove('/apk');
      await controller().install();
      expect(state().errorKind, UpdateErrorKind.download);
      expect(state().info, isNotNull, reason: 'информация о версии сохранена для повтора');

      server.serveBytes('/apk', apk);
      await controller().install();
      expect(state().phase, UpdatePhase.idle);
      expect(installer.installed, hasLength(1));
    });

    test('install без найденного обновления ничего не делает', () async {
      makeContainer();
      await controller().install();
      expect(state().phase, UpdatePhase.idle);
      expect(installer.installed, isEmpty);
    });
  });

  test('«Позже» закрывает предложение, но не пропускает версию', () async {
    latest = releaseOnServer(9);
    makeContainer();
    await controller().check();
    controller().dismiss();
    expect(state().phase, UpdatePhase.idle);
    expect(await container.read(updatePrefsProvider).skippedBuild(), isNull);
  });
}
