import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_columns.dart';
import '../../../core/database/watch.dart';
import '../../../core/domain/debt_kind.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../domain/debt_summary.dart';

/// Данные для создания/редактирования должника.
class DebtorInput {
  const DebtorInput({
    required this.name,
    this.shopName,
    this.address,
    this.note,
    this.phones = const [],
  });

  final String name;
  final String? shopName;
  final String? address;
  final String? note;

  /// Телефоны в любом формате; будут нормализованы. Дубликаты схлопываются.
  final List<String> phones;
}

/// Карточка должника: сводка + операции (новые сверху).
class DebtorDetails {
  const DebtorDetails({required this.summary, required this.transactions});

  final DebtorSummary summary;
  final List<DebtTransaction> transactions;
}

class DebtorsRepository {
  DebtorsRepository(this._db);

  final AppDatabase _db;

  // ---------- чтение ----------

  Future<List<DebtorSummary>> loadSummaries() async {
    final debtors = await (_db.select(_db.debtors)..where((t) => t.deletedAt.isNull())).get();
    final phones =
        await (_db.select(_db.debtorPhones)..where((t) => t.deletedAt.isNull())).get();
    final txs =
        await (_db.select(_db.debtTransactions)..where((t) => t.deletedAt.isNull())).get();
    return buildSummaries(debtors: debtors, phones: phones, transactions: txs);
  }

  /// Список должников; обновляется при любом изменении связанных таблиц.
  Stream<List<DebtorSummary>> watchSummaries() => _watch(loadSummaries);

  Stream<T> _watch<T>(Future<T> Function() load) =>
      watchTables(_db, [_db.debtors, _db.debtorPhones, _db.debtTransactions], load);

  Future<DebtorDetails?> loadDetails(String debtorId) async {
    final debtor = await (_db.select(_db.debtors)
          ..where((t) => t.id.equals(debtorId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (debtor == null) return null;
    final phones = await (_db.select(_db.debtorPhones)
          ..where((t) => t.debtorId.equals(debtorId) & t.deletedAt.isNull()))
        .get();
    final txs = await (_db.select(_db.debtTransactions)
          ..where((t) => t.debtorId.equals(debtorId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.occurredAt),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
    final summary =
        buildSummaries(debtors: [debtor], phones: phones, transactions: txs).single;
    return DebtorDetails(summary: summary, transactions: txs);
  }

  /// `null` в потоке — должник удалён или не существует.
  Stream<DebtorDetails?> watchDetails(String debtorId) =>
      _watch(() => loadDetails(debtorId));

  // ---------- должники ----------

  Future<String> createDebtor(DebtorInput input) {
    final cleaned = _validate(input);
    return _db.transaction(() async {
      final debtor = await _db.into(_db.debtors).insertReturning(
            DebtorsCompanion.insert(
              name: cleaned.name,
              shopName: Value(cleaned.shopName),
              address: Value(cleaned.address),
              note: Value(cleaned.note),
            ),
          );
      for (final phone in cleaned.phones) {
        await _insertPhone(debtor.id, phone);
      }
      return debtor.id;
    });
  }

  Future<void> updateDebtor(String id, DebtorInput input) {
    final cleaned = _validate(input);
    return _db.transaction(() async {
      await (_db.update(_db.debtors)..where((t) => t.id.equals(id))).write(
        DebtorsCompanion(
          name: Value(cleaned.name),
          shopName: Value(cleaned.shopName),
          address: Value(cleaned.address),
          note: Value(cleaned.note),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

      // Телефоны: удалённые — soft delete, новые — вставка, прежние не трогаем.
      final existing = await (_db.select(_db.debtorPhones)
            ..where((t) => t.debtorId.equals(id) & t.deletedAt.isNull()))
          .get();
      final wanted = cleaned.phones.toSet();
      for (final row in existing) {
        if (!wanted.contains(row.phone)) await _softDeletePhone(row.id);
      }
      final have = existing.map((r) => r.phone).toSet();
      for (final phone in cleaned.phones) {
        if (!have.contains(phone)) await _insertPhone(id, phone);
      }
    });
  }

  /// Soft delete должника вместе с его телефонами и операциями.
  Future<void> deleteDebtor(String id) {
    return _db.transaction(() async {
      final now = DateTime.now();
      await (_db.update(_db.debtorPhones)
            ..where((t) => t.debtorId.equals(id) & t.deletedAt.isNull()))
          .write(DebtorPhonesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ));
      await (_db.update(_db.debtTransactions)
            ..where((t) => t.debtorId.equals(id) & t.deletedAt.isNull()))
          .write(DebtTransactionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ));
      await (_db.update(_db.smsLogs)
            ..where((t) => t.debtorId.equals(id) & t.deletedAt.isNull()))
          .write(SmsLogsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ));
      await (_db.update(_db.debtors)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .write(DebtorsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ));
    });
  }

  // ---------- операции ----------

  Future<DebtTransaction> addTransaction({
    required String debtorId,
    required DebtKind kind,
    required int amount,
    required DateTime occurredAt,
    String? comment,
    String? orderId,
  }) {
    if (amount <= 0 || amount > maxAmount) {
      throw ArgumentError.value(amount, 'amount', 'Amount must be in 1..$maxAmount');
    }
    return _db.into(_db.debtTransactions).insertReturning(
          DebtTransactionsCompanion.insert(
            debtorId: debtorId,
            kind: kind,
            amount: amount,
            occurredAt: occurredAt,
            comment: Value(_blankToNull(comment)),
            orderId: Value(orderId),
          ),
        );
  }

  Future<void> deleteTransaction(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.debtTransactions)..where((t) => t.id.equals(id))).write(
      DebtTransactionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
  }

  // ---------- внутреннее ----------

  Future<void> _softDeletePhone(String id) {
    final now = DateTime.now();
    return (_db.update(_db.debtorPhones)..where((t) => t.id.equals(id))).write(
      DebtorPhonesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
  }

  Future<void> _insertPhone(String debtorId, String phone) =>
      _db.into(_db.debtorPhones).insert(
            DebtorPhonesCompanion.insert(debtorId: debtorId, phone: phone),
          );

  _Cleaned _validate(DebtorInput input) {
    final name = input.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.length > 120) {
      throw ArgumentError.value(input.name, 'name', 'Name must be 1..120 characters');
    }
    final phones = <String>[];
    for (final raw in input.phones) {
      if (raw.trim().isEmpty) continue;
      final normalized = normalizePhone(raw);
      if (normalized == null) throw ArgumentError.value(raw, 'phones', 'Invalid phone');
      if (!phones.contains(normalized)) phones.add(normalized);
    }
    return _Cleaned(
      name: name,
      shopName: _blankToNull(input.shopName),
      address: _blankToNull(input.address),
      note: _blankToNull(input.note),
      phones: phones,
    );
  }
}

String? _blankToNull(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

class _Cleaned {
  const _Cleaned({
    required this.name,
    required this.shopName,
    required this.address,
    required this.note,
    required this.phones,
  });

  final String name;
  final String? shopName;
  final String? address;
  final String? note;
  final List<String> phones;
}
