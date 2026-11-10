import 'package:flutter/material.dart';

import '../../features/debts/domain/debt_filter.dart';
import '../database/app_database.dart';

/// Настройки, которые нужны до первого кадра.
class AppSettingsSnapshot {
  const AppSettingsSnapshot({
    this.locale,
    this.themeMode = ThemeMode.system,
    this.debtFilter = const DebtFilterConfig(),
  });

  /// `null` — язык системы (с запасным вариантом uz).
  final Locale? locale;
  final ThemeMode themeMode;

  /// Пороги «просроченных» и «крупных» долгов.
  final DebtFilterConfig debtFilter;
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _localeKey = 'locale';
  static const _themeKey = 'theme_mode';
  static const _overdueDaysKey = 'debt_overdue_days';
  static const _largeDebtKey = 'debt_large_threshold';

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
      debtFilter: DebtFilterConfig(
        overdueDays: int.tryParse(map[_overdueDaysKey] ?? '') ??
            DebtFilterConfig.defaultOverdueDays,
        largeDebtThreshold: int.tryParse(map[_largeDebtKey] ?? '') ??
            DebtFilterConfig.defaultLargeDebtThreshold,
      ),
    );
  }

  Future<void> saveLocale(Locale? locale) => _put(_localeKey, locale?.languageCode);

  Future<void> saveThemeMode(ThemeMode mode) => _put(_themeKey, mode.name);

  Future<void> saveDebtFilter(DebtFilterConfig config) async {
    await _put(_overdueDaysKey, config.overdueDays.toString());
    await _put(_largeDebtKey, config.largeDebtThreshold.toString());
  }

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
