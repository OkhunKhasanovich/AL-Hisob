import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';
import 'package:al_savdogar/features/debts/domain/debt_filter.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });
  tearDown(() => db.close());

  test('текущая схема создаётся с нуля', () async {
    expect(db.schemaVersion, 3);
    final snapshot = await repo.load();
    expect(snapshot.locale, isNull);
    expect(snapshot.themeMode, ThemeMode.system);
  });

  test('язык и тема сохраняются и читаются', () async {
    await repo.saveLocale(const Locale('kaa'));
    await repo.saveThemeMode(ThemeMode.dark);

    final snapshot = await repo.load();
    expect(snapshot.locale, const Locale('kaa'));
    expect(snapshot.themeMode, ThemeMode.dark);
  });

  test('пороги долгов: значения по умолчанию и сохранение', () async {
    var snapshot = await repo.load();
    expect(snapshot.debtFilter.overdueDays, 30);
    expect(snapshot.debtFilter.largeDebtThreshold, 1000000);

    await repo.saveDebtFilter(
      const DebtFilterConfig(overdueDays: 14, largeDebtThreshold: 5000000),
    );
    snapshot = await repo.load();
    expect(snapshot.debtFilter.overdueDays, 14);
    expect(snapshot.debtFilter.largeDebtThreshold, 5000000);
  });

  test('null сбрасывает язык на системный', () async {
    await repo.saveLocale(const Locale('ru'));
    await repo.saveLocale(null);
    expect((await repo.load()).locale, isNull);
  });
}
