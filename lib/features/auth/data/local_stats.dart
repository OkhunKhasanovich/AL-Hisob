import '../../../core/database/app_database.dart';
import '../../../core/database/watch.dart';

/// Сколько записей пользователь накопил на телефоне (для предложения войти).
class LocalStatsRepository {
  LocalStatsRepository(this._db);

  final AppDatabase _db;

  Future<int> countRecords() async {
    Future<int> count(String table) async {
      final row = await _db.customSelect(
        'SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NULL',
        readsFrom: {},
      ).getSingle();
      return row.read<int>('c');
    }

    var total = 0;
    for (final table in ['debtors', 'debt_transactions', 'products', 'orders']) {
      total += await count(table);
    }
    return total;
  }

  Stream<int> watchRecordCount() => watchTables(
        _db,
        [_db.debtors, _db.debtTransactions, _db.products, _db.orders],
        countRecords,
      );
}
