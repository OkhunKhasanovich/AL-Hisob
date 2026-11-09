import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });
  tearDown(() => db.close());

  test('схема v1 создаётся с нуля', () async {
    expect(db.schemaVersion, 1);
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

  test('null сбрасывает язык на системный', () async {
    await repo.saveLocale(const Locale('ru'));
    await repo.saveLocale(null);
    expect((await repo.load()).locale, isNull);
  });
}
