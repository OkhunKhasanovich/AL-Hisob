/// Номер сборки, зашитый CI (`--dart-define=BUILD_NUMBER=<run_number>`).
/// В локальных сборках 0 — автообновление отключено.
const currentBuildNumber = int.fromEnvironment('BUILD_NUMBER');

/// Название версии из `pubspec.yaml` (`--dart-define=APP_VERSION=...` в CI).
const appVersionName = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// Репозиторий, из релизов которого берутся обновления.
const updateRepository = String.fromEnvironment(
  'UPDATE_REPO',
  defaultValue: 'OkhunKhasanovich/Al-Savdogar',
);

/// Новая версия приложения, найденная в релизах GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.build,
    required this.versionName,
    required this.apkUrl,
    required this.assetName,
    this.notes,
    this.size,
    this.sha256,
  });

  /// Номер сборки (`run_number`), по нему определяется «новее».
  final int build;
  final String versionName;
  final Uri apkUrl;
  final String assetName;

  /// Описание релиза (сообщение коммита).
  final String? notes;

  /// Размер файла в байтах (для проверки скачанного).
  final int? size;

  /// Контрольная сумма SHA-256 в нижнем регистре (если GitHub её отдал).
  final String? sha256;
}

/// Доверенные источники APK: только GitHub и его CDN, только HTTPS.
bool isTrustedUpdateHost(Uri uri) {
  if (uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return host == 'github.com' || host.endsWith('.githubusercontent.com');
}

final _tagPattern = RegExp(r'^build-(\d+)$');
final _versionPattern = RegExp(r'(\d+\.\d+\.\d+)');

/// Разбирает ответ `GET /repos/{repo}/releases/latest`.
///
/// Возвращает `null`, если это не наш релиз (тег не `build-N`), у релиза нет
/// подходящего APK для [abis] или ссылка ведёт не на GitHub.
/// [abis] — поддерживаемые телефоном архитектуры по убыванию предпочтения.
UpdateInfo? parseLatestRelease(Map<String, Object?> json, {required List<String> abis}) {
  if (json['draft'] == true || json['prerelease'] == true) return null;

  final tag = json['tag_name'];
  if (tag is! String) return null;
  final match = _tagPattern.firstMatch(tag);
  if (match == null) return null;
  final build = int.parse(match[1]!);

  final assets = json['assets'];
  if (assets is! List) return null;
  final byName = <String, Map<String, Object?>>{
    for (final a in assets)
      if (a is Map<String, Object?> && a['name'] is String) a['name']! as String: a,
  };

  for (final abi in abis) {
    final name = 'al-savdogar-$abi.apk';
    final asset = byName[name];
    if (asset == null) continue;

    final url = Uri.tryParse((asset['browser_download_url'] as String?) ?? '');
    if (url == null || !isTrustedUpdateHost(url)) continue;

    final digest = asset['digest'];
    final sha = digest is String && digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length).toLowerCase()
        : null;

    final title = (json['name'] as String?) ?? '';
    final notes = (json['body'] as String?)?.trim();
    return UpdateInfo(
      build: build,
      versionName: _versionPattern.firstMatch(title)?[1] ?? tag,
      apkUrl: url,
      assetName: name,
      notes: (notes == null || notes.isEmpty) ? null : notes,
      size: asset['size'] is int ? asset['size']! as int : null,
      sha256: sha,
    );
  }
  return null;
}

/// Обновление есть, если приложение — релизная сборка CI и в релизе номер больше.
bool isUpdateAvailable({required int currentBuild, required UpdateInfo latest}) =>
    currentBuild > 0 && latest.build > currentBuild;
