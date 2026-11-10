import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/settings/settings_providers.dart';
import '../data/android_apk_installer.dart';
import '../data/update_checker.dart';
import '../data/update_downloader.dart';
import '../data/update_prefs.dart';
import '../domain/apk_installer.dart';
import '../domain/update_info.dart';

/// Как часто проверять обновления при запуске.
const updateCheckInterval = Duration(hours: 6);

// ---------- зависимости (переопределяются в тестах) ----------

/// Номер текущей сборки; 0 — автообновление выключено.
final currentBuildProvider = Provider<int>((ref) => currentBuildNumber);

final apkInstallerProvider = Provider<ApkInstaller>(
  (ref) => Platform.isAndroid ? AndroidApkInstaller() : _NoInstaller(),
);

final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => UpdateChecker(
    currentBuild: ref.watch(currentBuildProvider),
    abis: ref.watch(apkInstallerProvider).supportedAbis,
  ),
);

/// Создаёт загрузчик (папка кэша приложения определяется асинхронно).
final updateDownloaderProvider = Provider<Future<UpdateDownloader> Function()>(
  (ref) => () async {
    final cache = await getTemporaryDirectory();
    return UpdateDownloader(directory: Directory('${cache.path}/updates'));
  },
);

final updatePrefsProvider = Provider<UpdatePrefs>(
  (ref) => UpdatePrefs(ref.watch(settingsRepositoryProvider)),
);

class _NoInstaller implements ApkInstaller {
  @override
  Future<List<String>> supportedAbis() async => const [];
  @override
  Future<InstallStatus> install(String apkPath) async => InstallStatus.failed;
  @override
  Future<void> openInstallSettings() async {}
}

// ---------- состояние ----------

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,

  /// Файл скачан и проверен, ждёт установки.
  ready,
  needsPermission,
  error,
}

enum UpdateErrorKind { check, download, verify, install }

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.info,
    this.progress = 0,
    this.errorKind,
    this.apkPath,
  });

  final UpdatePhase phase;
  final UpdateInfo? info;

  /// Доля скачанного, 0…1.
  final double progress;
  final UpdateErrorKind? errorKind;

  /// Скачанный и проверенный APK (фазы `ready`, `needsPermission`).
  final String? apkPath;
}

class UpdateController extends Notifier<UpdateState> {
  bool _busy = false;

  @override
  UpdateState build() => const UpdateState();

  bool get enabled => ref.read(currentBuildProvider) > 0;

  /// Проверка при запуске: не чаще раза в [updateCheckInterval], пропущенную
  /// пользователем версию молча игнорирует.
  Future<void> checkOnStartup() async {
    if (!enabled || _busy) return;
    final prefs = ref.read(updatePrefsProvider);
    final now = DateTime.now();
    final last = await prefs.lastCheck();
    if (last != null && now.difference(last) < updateCheckInterval) return;
    await prefs.setLastCheck(now);

    await _check(silentErrors: true, respectSkip: true);
  }

  /// Ручная проверка (кнопка в настройках): без ограничений и без «пропуска».
  Future<void> check() => _check(silentErrors: false, respectSkip: false);

  Future<void> _check({required bool silentErrors, required bool respectSkip}) async {
    if (!enabled || _busy) return;
    // Пока обновление качается или ждёт установки, повторная проверка не нужна.
    if (state.phase == UpdatePhase.downloading || state.phase == UpdatePhase.ready) return;
    _busy = true;
    if (!silentErrors) state = const UpdateState(phase: UpdatePhase.checking);
    try {
      final latest = await ref.read(updateCheckerProvider).check();
      if (latest == null) {
        state = UpdateState(phase: silentErrors ? UpdatePhase.idle : UpdatePhase.upToDate);
      } else if (respectSkip && await ref.read(updatePrefsProvider).skippedBuild() == latest.build) {
        state = const UpdateState();
      } else {
        state = UpdateState(phase: UpdatePhase.available, info: latest);
      }
    } on UpdateCheckException {
      state = silentErrors
          ? const UpdateState()
          : const UpdateState(phase: UpdatePhase.error, errorKind: UpdateErrorKind.check);
    } finally {
      _busy = false;
    }
  }

  /// Скачивает и проверяет APK, не мешая пользоваться приложением. Прогресс виден в состоянии;
  /// по окончании фаза `ready` — тогда можно предложить установку.
  Future<void> download() async {
    final info = state.info;
    if (info == null || _busy) return;
    _busy = true;
    try {
      final path = await _downloadFile(info);
      if (path != null) state = UpdateState(phase: UpdatePhase.ready, info: info, apkPath: path);
    } finally {
      _busy = false;
    }
  }

  /// Запускает установку; если файл ещё не скачан — сначала скачивает.
  Future<void> install() async {
    final info = state.info;
    if (info == null || _busy) return;
    _busy = true;
    try {
      final path = state.apkPath ?? await _downloadFile(info);
      if (path == null) return; // ошибка уже в состоянии

      final status = await ref.read(apkInstallerProvider).install(path);
      state = switch (status) {
        InstallStatus.started => UpdateState(phase: UpdatePhase.idle, info: info),
        InstallStatus.needsPermission =>
          UpdateState(phase: UpdatePhase.needsPermission, info: info, apkPath: path),
        InstallStatus.failed => UpdateState(
            phase: UpdatePhase.error,
            info: info,
            errorKind: UpdateErrorKind.install,
            apkPath: path,
          ),
      };
    } finally {
      _busy = false;
    }
  }

  /// Скачивание с проверкой. Возвращает путь к файлу или `null`, записав ошибку в состояние.
  Future<String?> _downloadFile(UpdateInfo info) async {
    state = UpdateState(phase: UpdatePhase.downloading, info: info);
    try {
      final downloader = await ref.read(updateDownloaderProvider)();
      final file = await downloader.download(
        info,
        onProgress: (p) => state = UpdateState(phase: UpdatePhase.downloading, info: info, progress: p),
      );
      return file.path;
    } on UpdateVerifyException {
      state = UpdateState(phase: UpdatePhase.error, info: info, errorKind: UpdateErrorKind.verify);
    } on UpdateDownloadException {
      state = UpdateState(phase: UpdatePhase.error, info: info, errorKind: UpdateErrorKind.download);
    } on FileSystemException {
      state = UpdateState(phase: UpdatePhase.error, info: info, errorKind: UpdateErrorKind.download);
    }
    return null;
  }

  Future<void> openInstallSettings() => ref.read(apkInstallerProvider).openInstallSettings();

  /// «Пропустить эту версию»: больше не показывать диалог при запуске.
  Future<void> skip() async {
    final info = state.info;
    if (info != null) await ref.read(updatePrefsProvider).skip(info.build);
    state = const UpdateState();
  }

  /// «Позже»: закрыть диалог до следующего запуска.
  void dismiss() {
    if (state.phase == UpdatePhase.downloading || state.phase == UpdatePhase.ready) return;
    state = const UpdateState();
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
