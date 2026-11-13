import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/debt_direction.dart';
import '../domain/debt_kind.dart';
import '../domain/order_status.dart';
import '../domain/product_unit.dart';
import '../domain/shop_role.dart';
import '../domain/sms_status.dart';
import 'schema_versions.dart';
import 'sync_columns.dart';
import 'tables/debts.dart';
import 'tables/orders.dart';
import 'tables/products.dart';
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

@DriftDatabase(tables: [AppSettings, ShopProfiles, Debtors, DebtorPhones, DebtTransactions, SmsTemplates, SmsLogs, Products, ProductPhotos, Orders, OrderItems, OrderStatusHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'al_hisob'));

  /// Увеличивать при каждом изменении схемы и выполнять
  /// `dart run drift_dev schema dump ...` (см. README).
  @override
  int get schemaVersion => 7;

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
          from4To5: (m, schema) async {
            await m.createTable(schema.products);
            await m.createTable(schema.productPhotos);
            await m.create(schema.idxProductPhotosProduct);
          },
          from5To6: (m, schema) async {
            await m.createTable(schema.orders);
            await m.createTable(schema.orderItems);
            await m.createTable(schema.orderStatusHistory);
            await m.create(schema.idxOrderItemsOrder);
            await m.create(schema.idxOrderHistoryOrder);
          },
          from6To7: (m, schema) async {
            // Сторона долга: у всех существующих записей «мне должны» (значение по умолчанию 0).
            await m.addColumn(schema.debtors, schema.debtors.direction);
          },
        ),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
