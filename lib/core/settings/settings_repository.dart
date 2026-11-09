import 'package:flutter/material.dart';

import '../database/app_database.dart';

/// Настройки, которые нужны до первого кадра.
class AppSettingsSnapshot {
  const AppSettingsSnapshot({this.locale, this.themeMode = ThemeMode.system});

  /// `null` — язык системы (с запасным вариантом uz).
  final Locale? locale;
  final ThemeMode themeMode;
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _localeKey = 'locale';
  static const _themeKey = 'theme_mode';

  Future<AppSettingsSnapshot> load() async {
    final rows = await _db.select(_db.appSettings).get();
    final map = {for (final r in rows) r.key: r.value};
    final localeCode = map[_localeKey];
    return AppSettingsSnapshot(
      locale: localeCode == null ? null : Locale(localeCode),
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == map[_themeKey],
        orElse: () => ThemeMode.system,
      ),
    );
  }

  Future<void> saveLocale(Locale? locale) => _put(_localeKey, locale?.languageCode);

  Future<void> saveThemeMode(ThemeMode mode) => _put(_themeKey, mode.name);

  Future<void> _put(String key, String? value) async {
    if (value == null) {
      await (_db.delete(_db.appSettings)..where((t) => t.key.equals(key))).go();
    } else {
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: key, value: value),
          );
    }
  }
}
