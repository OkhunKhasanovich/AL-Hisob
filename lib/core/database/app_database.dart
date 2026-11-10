import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/debt_kind.dart';
import '../domain/shop_role.dart';
import '../domain/sms_status.dart';
import 'schema_versions.dart';
import 'sync_columns.dart';
import 'tables/debts.dart';
import 'tables/shop_profiles.dart';
import 'tables/sms.dart';

part 'app_database.g.dart';

/// Локальные настройки приложения (язык, тема, интервалы напоминаний и т.п.).
/// Не синхронизируется, поэтому без [SyncColumns].
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [AppSettings, ShopProfiles, Debtors, DebtorPhones, DebtTransactions, SmsTemplates, SmsLogs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'al_savdogar'));

  /// Увеличивать при каждом изменении схемы и выполнять
  /// `dart run drift_dev schema dump ...` (см. README).
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: stepByStep(
          from1To2: (m, schema) async {
            await m.createTable(schema.shopProfiles);
          },
          from2To3: (m, schema) async {
            await m.createTable(schema.debtors);
            await m.createTable(schema.debtorPhones);
            await m.createTable(schema.debtTransactions);
            await m.create(schema.idxDebtorPhonesDebtor);
            await m.create(schema.idxDebtTransactionsDebtor);
          },
          from3To4: (m, schema) async {
            await m.createTable(schema.smsTemplates);
            await m.createTable(schema.smsLogs);
            await m.create(schema.idxSmsLogsDebtor);
          },
        ),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
