import 'package:flutter/material.dart';

import '../../features/debts/domain/debt_filter.dart';
import '../database/app_database.dart';

/// Настройки, которые нужны до первого кадра.
class AppSettingsSnapshot {
  const AppSettingsSnapshot({
    this.locale,
    this.themeMode = ThemeMode.system,
    this.debtFilter = const DebtFilterConfig(),
    this.smsPauseSeconds = defaultSmsPauseSeconds,
    this.debtsOverviewCompact = false,
  });

  static const defaultSmsPauseSeconds = 3;

  /// `null` — язык системы (с запасным вариантом uz).
  final Locale? locale;
  final ThemeMode themeMode;

  /// Пороги «просроченных» и «крупных» долгов.
  final DebtFilterConfig debtFilter;

  /// Пауза между SMS при массовой рассылке, секунды (1–30).
  final int smsPauseSeconds;

  /// Верхняя карточка «Долги» в тонком виде (без графика).
  final bool debtsOverviewCompact;
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _localeKey = 'locale';
  static const _themeKey = 'theme_mode';
  static const _overdueDaysKey = 'debt_overdue_days';
  static const _largeDebtKey = 'debt_large_threshold';
  static const _smsPauseKey = 'sms_pause_seconds';
  static const _overviewCompactKey = 'debts_overview_compact';

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
      smsPauseSeconds: (int.tryParse(map[_smsPauseKey] ?? '') ??
              AppSettingsSnapshot.defaultSmsPauseSeconds)
          .clamp(1, 30),
      debtsOverviewCompact: map[_overviewCompactKey] == '1',
    );
  }

  Future<void> saveLocale(Locale? locale) => _put(_localeKey, locale?.languageCode);

  Future<void> saveThemeMode(ThemeMode mode) => _put(_themeKey, mode.name);

  Future<void> saveDebtsOverviewCompact(bool compact) => _put(_overviewCompactKey, compact ? '1' : null);

  /// Произвольные числовые настройки (служебные метки вроде «когда проверяли обновление»).
  Future<int?> readInt(String key) async {
    final row = await (_db.select(_db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return int.tryParse(row?.value ?? '');
  }

  Future<void> writeInt(String key, int value) => _put(key, value.toString());

  Future<void> saveSmsPauseSeconds(int seconds) =>
      _put(_smsPauseKey, seconds.clamp(1, 30).toString());

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
