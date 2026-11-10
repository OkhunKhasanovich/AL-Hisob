import '../../../core/settings/settings_repository.dart';

/// Служебные метки автообновления в локальных настройках.
class UpdatePrefs {
  UpdatePrefs(this._settings);

  final SettingsRepository _settings;

  static const _lastCheckKey = 'update_last_check_ms';
  static const _skippedBuildKey = 'update_skipped_build';

  Future<DateTime?> lastCheck() async {
    final ms = await _settings.readInt(_lastCheckKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastCheck(DateTime time) =>
      _settings.writeInt(_lastCheckKey, time.millisecondsSinceEpoch);

  /// Номер сборки, которую пользователь пропустил.
  Future<int?> skippedBuild() => _settings.readInt(_skippedBuildKey);

  Future<void> skip(int build) => _settings.writeInt(_skippedBuildKey, build);
}
