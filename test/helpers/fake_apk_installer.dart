import 'package:al_savdogar/features/update/domain/apk_installer.dart';

class FakeApkInstaller implements ApkInstaller {
  FakeApkInstaller({this.status = InstallStatus.started, this.abis = const ['arm64-v8a']});

  InstallStatus status;
  List<String> abis;
  final installed = <String>[];
  int settingsOpened = 0;

  @override
  Future<List<String>> supportedAbis() async => abis;

  @override
  Future<InstallStatus> install(String apkPath) async {
    installed.add(apkPath);
    return status;
  }

  @override
  Future<void> openInstallSettings() async => settingsOpened++;
}
