import 'package:flutter/services.dart';

import '../domain/apk_installer.dart';

/// Установка APK через системный установщик Android (код — `UpdateBridge.kt`).
class AndroidApkInstaller implements ApkInstaller {
  AndroidApkInstaller({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('uz.alhisob.app/update');

  final MethodChannel _channel;

  @override
  Future<List<String>> supportedAbis() async {
    try {
      final abis = await _channel.invokeListMethod<String>('supportedAbis');
      return abis ?? const ['arm64-v8a'];
    } on PlatformException {
      return const ['arm64-v8a'];
    } on MissingPluginException {
      return const ['arm64-v8a'];
    }
  }

  @override
  Future<InstallStatus> install(String apkPath) async {
    try {
      final status = await _channel.invokeMethod<String>('install', {'path': apkPath});
      return switch (status) {
        'started' => InstallStatus.started,
        'needs_permission' => InstallStatus.needsPermission,
        _ => InstallStatus.failed,
      };
    } on PlatformException {
      return InstallStatus.failed;
    } on MissingPluginException {
      return InstallStatus.failed;
    }
  }

  @override
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException {
      // нечего делать
    } on MissingPluginException {
      // то же
    }
  }
}
