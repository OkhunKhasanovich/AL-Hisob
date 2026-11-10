enum InstallStatus {
  /// Системный установщик открыт, дальше пользователь подтверждает установку.
  started,

  /// Нужно разрешить установку из этого приложения в настройках Android.
  needsPermission,

  failed,
}

/// Запуск установки скачанного APK. Реализация для Android — `AndroidApkInstaller`.
abstract interface class ApkInstaller {
  /// Поддерживаемые архитектуры телефона по убыванию предпочтения
  /// (например `arm64-v8a`, `armeabi-v7a`).
  Future<List<String>> supportedAbis();

  Future<InstallStatus> install(String apkPath);

  /// Открывает настройки «Установка неизвестных приложений» для этого приложения.
  Future<void> openInstallSettings();
}
