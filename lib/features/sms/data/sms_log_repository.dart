import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_columns.dart';
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

  Stream<List<SmsLog>> watchForDebtor(String debtorId) {
    late final StreamController<List<SmsLog>> controller;
    StreamSubscription<Set<TableUpdate>>? sub;
    var generation = 0;

    Future<void> emit() async {
      final mine = ++generation;
      try {
        final value = await forDebtor(debtorId);
        if (mine == generation && !controller.isClosed) controller.add(value);
      } catch (e, st) {
        if (mine == generation && !controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<List<SmsLog>>(
      onListen: () {
        sub = _db
            .tableUpdates(TableUpdateQuery.onTable(_db.smsLogs))
            .listen((_) => emit());
        emit();
      },
      onCancel: () async {
        await sub?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

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
