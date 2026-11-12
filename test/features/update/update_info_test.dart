import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/features/update/domain/update_info.dart';

/// Ответ GitHub API `releases/latest` (сокращённый, форма реальная).
Map<String, Object?> release({
  String tag = 'build-12',
  String name = 'Al-Hisob 0.1.0 (12)',
  String? body = 'feat: updater',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, Object?>>? assets,
}) =>
    {
      'tag_name': tag,
      'name': name,
      'body': body,
      'draft': draft,
      'prerelease': prerelease,
      'assets': assets ??
          [
            asset('al-hisob-arm64-v8a.apk', size: 26000000, digest: 'sha256:ABCDEF0123'),
            asset('al-hisob-armeabi-v7a.apk', size: 24000000),
            asset('al-hisob-x86_64.apk', size: 27000000),
          ],
    };

Map<String, Object?> asset(String name, {int? size, String? digest, String? url}) => {
      'name': name,
      'size': size,
      'digest': digest,
      'browser_download_url':
          url ?? 'https://github.com/OkhunKhasanovich/Al-Hisob/releases/download/build-12/$name',
    };

void main() {
  group('parseLatestRelease', () {
    test('берёт APK под первую подходящую архитектуру', () {
      final info = parseLatestRelease(release(), abis: ['arm64-v8a', 'armeabi-v7a'])!;
      expect(info.assetName, 'al-hisob-arm64-v8a.apk');
      expect(info.build, 12);
      expect(info.versionName, '0.1.0');
      expect(info.notes, 'feat: updater');
      expect(info.size, 26000000);
      expect(info.apkUrl.host, 'github.com');
    });

    test('порядок предпочтения архитектур важен', () {
      final info = parseLatestRelease(release(), abis: ['armeabi-v7a', 'arm64-v8a'])!;
      expect(info.assetName, 'al-hisob-armeabi-v7a.apk');
    });

    test('архитектуры нет в релизе — идём дальше по списку', () {
      final r = release(assets: [asset('al-hisob-armeabi-v7a.apk')]);
      expect(parseLatestRelease(r, abis: ['arm64-v8a', 'armeabi-v7a'])!.assetName,
          'al-hisob-armeabi-v7a.apk');
    });

    test('нет подходящего APK — null', () {
      final r = release(assets: [asset('al-hisob-x86_64.apk')]);
      expect(parseLatestRelease(r, abis: ['arm64-v8a']), isNull);
      expect(parseLatestRelease(release(assets: const []), abis: ['arm64-v8a']), isNull);
      expect(parseLatestRelease(release(), abis: const []), isNull);
    });

    test('контрольная сумма: префикс sha256: снимается, регистр нижний', () {
      expect(parseLatestRelease(release(), abis: ['arm64-v8a'])!.sha256, 'abcdef0123');
      final noDigest = release(assets: [asset('al-hisob-arm64-v8a.apk')]);
      expect(parseLatestRelease(noDigest, abis: ['arm64-v8a'])!.sha256, isNull);
      final other = release(assets: [asset('al-hisob-arm64-v8a.apk', digest: 'md5:abc')]);
      expect(parseLatestRelease(other, abis: ['arm64-v8a'])!.sha256, isNull);
    });

    test('чужие теги, черновики и пре-релизы игнорируются', () {
      expect(parseLatestRelease(release(tag: 'v1.0.0'), abis: ['arm64-v8a']), isNull);
      expect(parseLatestRelease(release(tag: 'build-x'), abis: ['arm64-v8a']), isNull);
      expect(parseLatestRelease(release(draft: true), abis: ['arm64-v8a']), isNull);
      expect(parseLatestRelease(release(prerelease: true), abis: ['arm64-v8a']), isNull);
    });

    test('ссылка не на GitHub — не доверяем', () {
      for (final url in [
        'https://evil.example.com/al-hisob-arm64-v8a.apk',
        'http://github.com/x/al-hisob-arm64-v8a.apk',
        'https://github.com.evil.com/a.apk',
      ]) {
        final r = release(assets: [asset('al-hisob-arm64-v8a.apk', url: url)]);
        expect(parseLatestRelease(r, abis: ['arm64-v8a']), isNull, reason: url);
      }
    });

    test('CDN GitHub допустим', () {
      final r = release(assets: [
        asset('al-hisob-arm64-v8a.apk',
            url: 'https://objects.githubusercontent.com/github-production-release-asset/abc')
      ]);
      expect(parseLatestRelease(r, abis: ['arm64-v8a']), isNotNull);
    });

    test('пустое описание → null, нет номера версии в названии → берётся тег', () {
      final info = parseLatestRelease(release(body: '  ', name: 'Release'), abis: ['arm64-v8a'])!;
      expect(info.notes, isNull);
      expect(info.versionName, 'build-12');
    });

    test('мусор в JSON не приводит к исключению', () {
      expect(parseLatestRelease({}, abis: ['arm64-v8a']), isNull);
      expect(parseLatestRelease({'tag_name': 5}, abis: ['arm64-v8a']), isNull);
      expect(parseLatestRelease({'tag_name': 'build-1', 'assets': 'x'}, abis: ['arm64-v8a']), isNull);
    });
  });

  group('isUpdateAvailable', () {
    UpdateInfo info(int build) => UpdateInfo(
          build: build,
          versionName: '0.1.0',
          apkUrl: Uri.parse('https://github.com/x/a.apk'),
          assetName: 'a.apk',
        );

    test('новее — да; та же или старее — нет', () {
      expect(isUpdateAvailable(currentBuild: 5, latest: info(6)), isTrue);
      expect(isUpdateAvailable(currentBuild: 5, latest: info(5)), isFalse);
      expect(isUpdateAvailable(currentBuild: 5, latest: info(4)), isFalse);
    });

    test('сборка для разработки (0) не обновляется', () {
      expect(isUpdateAvailable(currentBuild: 0, latest: info(99)), isFalse);
    });

    test('номера сравниваются как числа, а не строки', () {
      expect(isUpdateAvailable(currentBuild: 9, latest: info(10)), isTrue);
      expect(isUpdateAvailable(currentBuild: 100, latest: info(99)), isFalse);
    });
  });

  test('isTrustedUpdateHost', () {
    expect(isTrustedUpdateHost(Uri.parse('https://github.com/a/b')), isTrue);
    expect(isTrustedUpdateHost(Uri.parse('https://release-assets.githubusercontent.com/x')), isTrue);
    expect(isTrustedUpdateHost(Uri.parse('https://githubusercontent.com.evil.io/x')), isFalse);
    expect(isTrustedUpdateHost(Uri.parse('http://github.com/a')), isFalse);
    expect(isTrustedUpdateHost(Uri.parse('https://example.com/a')), isFalse);
  });
}
