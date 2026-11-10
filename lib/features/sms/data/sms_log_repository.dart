import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_columns.dart';
import '../../../core/database/watch.dart';
import '../../../core/domain/sms_status.dart';

class SmsLogRepository {
  SmsLogRepository(this._db);

  final AppDatabase _db;

  Future<SmsLog> add({
    required String debtorId,
    required String phone,
    required String body,
    required SmsStatus status,
    String? error,
  }) =>
      _db.into(_db.smsLogs).insertReturning(
            SmsLogsCompanion.insert(
              debtorId: debtorId,
              phone: phone,
              body: body,
              status: status,
              error: Value(error),
            ),
          );

  /// Журнал должника: новые сверху.
  Future<List<SmsLog>> forDebtor(String debtorId) =>
      (_db.select(_db.smsLogs)
            ..where((t) => t.debtorId.equals(debtorId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Stream<List<SmsLog>> watchForDebtor(String debtorId) =>
      watchTables(_db, [_db.smsLogs], () => forDebtor(debtorId));

  Future<void> softDeleteForDebtor(String debtorId) {
    final now = DateTime.now();
    return (_db.update(_db.smsLogs)
          ..where((t) => t.debtorId.equals(debtorId) & t.deletedAt.isNull()))
        .write(SmsLogsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      syncStatus: const Value(SyncStatus.pending),
    ));
  }
}
