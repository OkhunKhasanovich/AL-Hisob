import 'package:drift/drift.dart';

import '../../domain/debt_kind.dart';
import '../sync_columns.dart';

/// Должник (покупатель, которому дали товар в долг).
class Debtors extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get shopName => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get note => text().nullable()();
}

/// Телефоны должника (у одного может быть несколько). Хранятся в
/// нормализованном виде `+998XXXXXXXXX`.
@TableIndex(name: 'idx_debtor_phones_debtor', columns: {#debtorId})
class DebtorPhones extends Table with SyncColumns {
  TextColumn get debtorId => text().references(Debtors, #id)();
  TextColumn get phone => text()();
}

/// Операции «дал в долг» / «получил оплату». Сумма всегда положительная
/// (целые сумы), знак задаёт [kind]. Баланс считается из операций.
@TableIndex(name: 'idx_debt_transactions_debtor', columns: {#debtorId})
class DebtTransactions extends Table with SyncColumns {
  TextColumn get debtorId => text().references(Debtors, #id)();
  IntColumn get kind => intEnum<DebtKind>()();
  // ignore: recursive_getters
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get comment => text().nullable()();

  /// Привязка к заказу (таблица заказов появится на этапе 6).
  TextColumn get orderId => text().nullable()();
}
