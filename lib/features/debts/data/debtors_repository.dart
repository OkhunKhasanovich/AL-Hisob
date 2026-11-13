import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_columns.dart';
import '../../../core/database/watch.dart';
import '../../../core/domain/debt_kind.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../domain/debt_summary.dart';
import '../domain/demo_data.dart';

/// Данные для создания/редактирования должника.
class DebtorInput {
  const DebtorInput({
    required this.name,
    this.shopName,
    this.address,
    this.note,
    this.phones = const [],
    this.initialDebt = 0,
    this.initialDebtComment,
  });

  final String name;
  final String? shopName;
  final String? address;
  final String? note;

  /// Телефоны в любом формате; будут нормализованы. Дубликаты схлопываются.
  final List<String> phones;

  /// Текущий долг, который торговец переносит из тетради при заведении должника.
  /// Только при создании: превращается в обычную операцию «долг» на сегодня.
  final int initialDebt;
  final String? initialDebtComment;
}

/// Карточка должника: сводка + операции (новые сверху).
class DebtorDetails {
  const DebtorDetails({required this.summary, required this.transactions});

  final DebtorSummary summary;
  final List<DebtTransaction> transactions;
}

/// Оплата больше текущего долга: так записать нельзя, иначе у должника появилась бы «переплата».
class PaymentExceedsDebtException implements Exception {
  PaymentExceedsDebtException({required this.balance});

  /// Текущий долг (0, если долга нет): больше этой суммы принять нельзя.
  final int balance;

  @override
  String toString() => 'PaymentExceedsDebtException(balance: $balance)';
}

/// Удаление долговой записи оставило бы больше оплат, чем долгов (получилась бы переплата).
class DeletionCausesOverpaymentException implements Exception {
  DeletionCausesOverpaymentException({required this.balanceAfter});

  final int balanceAfter;

  @override
  String toString() => 'DeletionCausesOverpaymentException(balanceAfter: $balanceAfter)';
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

  /// Действующие операции действующих должников — для графика динамики долга.
  Future<List<DebtTransaction>> loadActiveTransactions() async {
    final debtors = await (_db.select(_db.debtors)..where((t) => t.deletedAt.isNull())).get();
    final ids = {for (final d in debtors) d.id};
    final txs =
        await (_db.select(_db.debtTransactions)..where((t) => t.deletedAt.isNull())).get();
    return [for (final t in txs) if (ids.contains(t.debtorId)) t];
  }

  Stream<List<DebtTransaction>> watchActiveTransactions() =>
      watchTables(_db, [_db.debtors, _db.debtTransactions], loadActiveTransactions);

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
      if (input.initialDebt > 0) {
        // Перенос из тетради — обычная операция, она попадает в историю и в баланс.
        await addTransaction(
          debtorId: debtor.id,
          kind: DebtKind.debt,
          amount: input.initialDebt,
          occurredAt: DateTime.now(),
          comment: input.initialDebtComment,
        );
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

  // ---------- тестовые данные ----------

  /// Добавляет [count] тестовых должников с историей операций (для знакомства с приложением).
  /// Возвращает, сколько добавлено. У них в заметке стоит [demoDebtorNote].
  Future<int> seedDemoDebtors({int count = 50, DateTime? now, Random? random}) async {
    final today = now ?? DateTime.now();
    final demo = generateDemoDebtors(count, random ?? Random());
    await _db.transaction(() async {
      for (final d in demo) {
        final id = await createDebtor(DebtorInput(
          name: d.name,
          shopName: d.shopName,
          address: d.address,
          note: demoDebtorNote,
          phones: [d.phone],
        ));
        for (final op in d.operations) {
          await addTransaction(
            debtorId: id,
            kind: op.kind,
            amount: op.amount,
            occurredAt: DateTime(today.year, today.month, today.day - op.daysAgo, op.hour),
          );
        }
      }
    });
    return demo.length;
  }

  /// Сколько сейчас тестовых должников.
  Future<int> countDemoDebtors() async {
    final rows = await (_db.select(_db.debtors)
          ..where((t) => t.deletedAt.isNull() & t.note.equals(demoDebtorNote)))
        .get();
    return rows.length;
  }

  /// Удаляет (soft delete) всех тестовых должников. Возвращает, сколько удалено.
  Future<int> deleteDemoDebtors() async {
    final rows = await (_db.select(_db.debtors)
          ..where((t) => t.deletedAt.isNull() & t.note.equals(demoDebtorNote)))
        .get();
    await _db.transaction(() async {
      for (final d in rows) {
        await deleteDebtor(d.id);
      }
    });
    return rows.length;
  }

  // ---------- операции ----------

  /// Добавляет операцию. Оплата не может быть больше текущего долга: иначе бросает
  /// [PaymentExceedsDebtException] и ничего не записывает (проверка и запись — одной транзакцией).
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
    return _db.transaction(() async {
      if (kind == DebtKind.payment) {
        final balance = await _balance(debtorId);
        if (amount > balance) throw PaymentExceedsDebtException(balance: balance < 0 ? 0 : balance);
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
    });
  }

  /// Удаляет операцию (мягко). Долговую запись нельзя удалить, если после этого оплат
  /// окажется больше долгов: бросает [DeletionCausesOverpaymentException].
  Future<void> deleteTransaction(String id) {
    return _db.transaction(() async {
      final tx = await (_db.select(_db.debtTransactions)
            ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (tx == null) return;
      if (tx.kind == DebtKind.debt) {
        final after = await _balance(tx.debtorId) - tx.amount;
        if (after < 0) throw DeletionCausesOverpaymentException(balanceAfter: after);
      }
      final now = DateTime.now();
      await (_db.update(_db.debtTransactions)..where((t) => t.id.equals(id))).write(
        DebtTransactionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
    });
  }

  /// Текущий долг по действующим операциям: выдано минус полученные оплаты.
  Future<int> _balance(String debtorId) async {
    final rows = await (_db.select(_db.debtTransactions)
          ..where((t) => t.debtorId.equals(debtorId) & t.deletedAt.isNull()))
        .get();
    var balance = 0;
    for (final r in rows) {
      balance += r.kind == DebtKind.debt ? r.amount : -r.amount;
    }
    return balance;
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
    if (input.initialDebt < 0 || input.initialDebt > maxAmount) {
      throw ArgumentError.value(input.initialDebt, 'initialDebt', 'Amount must be in 0..$maxAmount');
    }
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
