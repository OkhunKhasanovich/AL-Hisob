import 'package:drift/drift.dart';

import '../../domain/order_status.dart';
import '../../domain/product_unit.dart';
import '../sync_columns.dart';
import 'debts.dart';

/// Заказ. Покупатель — запись из книги должников ([customerId]).
class Orders extends Table with SyncColumns {
  /// Человекочитаемый номер (1, 2, 3…) в пределах этого устройства.
  IntColumn get number => integer()();

  TextColumn get customerId => text().references(Debtors, #id)();
  IntColumn get status => intEnum<OrderStatus>()();
  TextColumn get comment => text().nullable()();

  /// Сумма заказа в сумах (сумма строк).
  IntColumn get total => integer()();

  /// Сколько покупатель заплатил при доставке.
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();
}

/// Позиция заказа. Название, единица и цены копируются из каталога на момент
/// заказа, чтобы позднейшие правки каталога не меняли старые заказы.
@TableIndex(name: 'idx_order_items_order', columns: {#orderId})
class OrderItems extends Table with SyncColumns {
  TextColumn get orderId => text().references(Orders, #id)();

  /// Товар каталога (без внешнего ключа: товар могут удалить).
  TextColumn get productId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get unit => intEnum<ProductUnit>()();
  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get packSize => integer().nullable()();
  IntColumn get packPrice => integer().nullable()();
  IntColumn get lineTotal => integer()();
  IntColumn get position => integer()();
}

/// История заказа: кто и когда сменил статус (или изменил состав).
@TableIndex(name: 'idx_order_history_order', columns: {#orderId})
class OrderStatusHistory extends Table with SyncColumns {
  TextColumn get orderId => text().references(Orders, #id)();
  IntColumn get status => intEnum<OrderStatus>()();

  /// Название магазина/имя того, кто выполнил действие.
  TextColumn get actorName => text()();
  TextColumn get note => text().nullable()();

  /// Запись об изменении состава заказа (статус остался прежним).
  BoolColumn get isEdit => boolean().withDefault(const Constant(false))();
}
