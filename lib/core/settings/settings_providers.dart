import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/debts/domain/debt_filter.dart';
import '../database/app_database.dart';
import '../widgets/app_backdrop.dart';
import 'settings_repository.dart';

/// Переопределяется в `main()` открытой БД.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

/// Переопределяется в `main()` настройками, загруженными до runApp,
/// чтобы не было мигания языка/темы при старте.
final initialSettingsProvider = Provider<AppSettingsSnapshot>(
  (ref) => const AppSettingsSnapshot(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

/// Выбранный пользователем язык. `null` — следовать языку системы.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => ref.watch(initialSettingsProvider).locale;

  Future<void> select(Locale? locale) async {
    state = locale;
    await ref.read(settingsRepositoryProvider).saveLocale(locale);
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(LocaleController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialSettingsProvider).themeMode;

  Future<void> select(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsRepositoryProvider).saveThemeMode(mode);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class BackdropController extends Notifier<AppBackdropStyle> {
  @override
  AppBackdropStyle build() => ref.watch(initialSettingsProvider).backdrop;

  Future<void> select(AppBackdropStyle style) async {
    state = style;
    await ref.read(settingsRepositoryProvider).saveBackdrop(style);
  }
}

/// Фон под стеклянными карточками (узор / сияние / без фона).
final backdropStyleProvider =
    NotifierProvider<BackdropController, AppBackdropStyle>(BackdropController.new);

class DebtFilterConfigController extends Notifier<DebtFilterConfig> {
  @override
  DebtFilterConfig build() => ref.watch(initialSettingsProvider).debtFilter;

  Future<void> update({int? overdueDays, int? largeDebtThreshold}) async {
    state = DebtFilterConfig(
      overdueDays: overdueDays ?? state.overdueDays,
      largeDebtThreshold: largeDebtThreshold ?? state.largeDebtThreshold,
    );
    await ref.read(settingsRepositoryProvider).saveDebtFilter(state);
  }
}

final debtFilterConfigProvider =
    NotifierProvider<DebtFilterConfigController, DebtFilterConfig>(
        DebtFilterConfigController.new);

class SmsPauseController extends Notifier<int> {
  @override
  int build() => ref.watch(initialSettingsProvider).smsPauseSeconds;

  Future<void> set(int seconds) async {
    state = seconds.clamp(1, 30);
    await ref.read(settingsRepositoryProvider).saveSmsPauseSeconds(state);
  }
}

/// Пауза между SMS в массовой рассылке, секунды.
final smsPauseSecondsProvider =
    NotifierProvider<SmsPauseController, int>(SmsPauseController.new);
