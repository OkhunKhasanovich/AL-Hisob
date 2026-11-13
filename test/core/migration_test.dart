import 'package:drift/drift.dart' show Variable;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/debt_direction.dart';

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v6.dart' as v6;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in [1, 2, 3, 4, 5, 6]) {
    test('миграция v$from → v7 даёт ту же схему, что и создание с нуля', () async {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, 7);
    });
  }

  test('v6 → v7: существующие должники остаются «мне должны», данные целы', () async {
    final schema = await verifier.schemaAt(6);
    final old = v6.DatabaseAtV6(schema.newConnection());
    await old.customStatement(
      "INSERT INTO debtors (id, created_at, updated_at, sync_status, name) "
      "VALUES ('d-1', '2026-01-01T00:00:00.000', '2026-01-01T00:00:00.000', 1, 'Alisher')",
    );
    await old.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 7);

    final rows = await db.select(db.debtors).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Alisher');
    expect(rows.single.direction, DebtDirection.receivable);
    // В SQL лежит число 0: на сервер и в старые версии приложения уходит оно.
    final raw = await db
        .customSelect('SELECT direction FROM debtors WHERE id = ?', variables: [Variable.withString('d-1')])
        .getSingle();
    expect(raw.read<int>('direction'), 0);
  });
}
