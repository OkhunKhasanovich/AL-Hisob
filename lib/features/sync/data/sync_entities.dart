import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_columns.dart';

/// Одна синхронизируемая таблица. Знает, как достать изменённые строки, прочитать
/// строку по id и записать пришедшую с сервера. Вся работа идёт через JSON строки
/// (`DataClass.toJson`), поэтому движок не зависит от конкретных колонок.
class SyncEntity {
  SyncEntity._(this.name, this._pending, this._pendingCount, this._byId, this._upsert, this._markSynced);

  /// Имя совпадает с именем таблицы и с белым списком на сервере.
  final String name;

  final Future<List<Map<String, Object?>>> Function(int limit) _pending;
  final Future<int> Function() _pendingCount;
  final Future<Map<String, Object?>?> Function(String id) _byId;
  final Future<void> Function(Map<String, Object?> json) _upsert;
  final Future<void> Function(String id) _markSynced;

  static SyncEntity of<T extends Table, D extends DataClass>(
    AppDatabase db,
    TableInfo<T, D> table,
    D Function(Map<String, dynamic> json) fromJson, {
    // Значения для полей, которых нет в записи от более старой версии приложения
    // (появились позже): иначе такая запись не разбиралась бы и терялась.
    Map<String, Object?> defaults = const {},
  }) {
    final name = table.actualTableName;
    Map<String, Object?> encode(D row) => row.toJson().cast<String, Object?>();
    Future<List<D>> select(String where, List<Variable> variables) async {
      final rows = await db
          .customSelect('SELECT * FROM $name WHERE $where', variables: variables, readsFrom: {table})
          .get();
      return [for (final r in rows) await table.map(r.data)];
    }

    return SyncEntity._(
      name,
      (limit) async => [
        for (final row in await select('sync_status = ? LIMIT ?', [
          Variable.withInt(SyncStatus.pending.index),
          Variable.withInt(limit),
        ]))
          encode(row),
      ],
      () async {
        final r = await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM $name WHERE sync_status = ?',
              variables: [Variable.withInt(SyncStatus.pending.index)],
              readsFrom: {table},
            )
            .getSingle();
        return r.read<int>('n');
      },
      (id) async {
        final rows = await select('id = ?', [Variable.withString(id)]);
        return rows.isEmpty ? null : encode(rows.first);
      },
      (json) async {
        final row = fromJson({...defaults, ...json, 'syncStatus': SyncStatus.synced.index});
        await db.into(table).insert(row as Insertable<D>, mode: InsertMode.insertOrReplace);
      },
      (id) => db.customUpdate(
        'UPDATE $name SET sync_status = ? WHERE id = ?',
        variables: [Variable.withInt(SyncStatus.synced.index), Variable.withString(id)],
        updates: {table},
        updateKind: UpdateKind.update,
      ),
    );
  }

  /// Строки, изменённые на устройстве и ещё не отправленные.
  Future<List<Map<String, Object?>>> pending(int limit) => _pending(limit);

  Future<int> pendingCount() => _pendingCount();

  Future<Map<String, Object?>?> byId(String id) => _byId(id);

  /// Записывает пришедшую версию как «совпадает с сервером».
  Future<void> upsertSynced(Map<String, Object?> json) => _upsert(json);

  /// Помечает строку отправленной, только если она не менялась с момента отправки
  /// ([sent] — то, что ушло на сервер): правка во время запроса останется «ждёт отправки».
  Future<void> markSyncedIfUnchanged(String id, Map<String, Object?> sent) async {
    final now = await _byId(id);
    if (now == null) return;
    if (_sameData(now, sent)) await _markSynced(id);
  }

  static bool _sameData(Map<String, Object?> a, Map<String, Object?> b) {
    for (final key in {...a.keys, ...b.keys}) {
      if (key == 'syncStatus') continue;
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}

/// Все синхронизируемые таблицы. Порядок — от родителей к детям.
List<SyncEntity> buildSyncEntities(AppDatabase db) => [
      SyncEntity.of(db, db.shopProfiles, ShopProfile.fromJson),
      // `direction`: запись от версии без этого поля — «мне должны» (0).
      SyncEntity.of(db, db.debtors, Debtor.fromJson, defaults: const {'direction': 0}),
      SyncEntity.of(db, db.debtorPhones, DebtorPhone.fromJson),
      SyncEntity.of(db, db.debtTransactions, DebtTransaction.fromJson),
      SyncEntity.of(db, db.smsTemplates, SmsTemplate.fromJson),
      SyncEntity.of(db, db.smsLogs, SmsLog.fromJson),
      SyncEntity.of(db, db.products, Product.fromJson),
      SyncEntity.of(db, db.productPhotos, ProductPhoto.fromJson),
      SyncEntity.of(db, db.orders, Order.fromJson),
      SyncEntity.of(db, db.orderItems, OrderItem.fromJson),
      SyncEntity.of(db, db.orderStatusHistory, OrderStatusHistoryData.fromJson),
    ];
