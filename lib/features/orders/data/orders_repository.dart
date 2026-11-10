import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_columns.dart';
import '../../../core/database/watch.dart';
import '../../../core/domain/debt_kind.dart';
import '../../../core/domain/order_status.dart';
import '../../../core/utils/money.dart';
import '../domain/order_models.dart';
import '../domain/order_workflow.dart';

/// Попытка перейти в статус, недоступный из текущего.
class InvalidOrderTransition implements Exception {
  InvalidOrderTransition(this.from, this.to);

  final OrderStatus from;
  final OrderStatus to;

  @override
  String toString() => 'InvalidOrderTransition: ${from.name} → ${to.name}';
}

const maxOrderItems = 200;
const maxItemQuantity = 9999999;

class OrdersRepository {
  OrdersRepository(this._db);

  final AppDatabase _db;

  // ---------- чтение ----------

  /// Заказы, новые сверху.
  Future<List<OrderSummary>> loadSummaries() async {
    final orders = await (_db.select(_db.orders)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.number)]))
        .get();
    final names = await _customerNames();
    final items = await (_db.select(_db.orderItems)..where((t) => t.deletedAt.isNull())).get();
    final counts = <String, int>{};
    for (final i in items) {
      counts[i.orderId] = (counts[i.orderId] ?? 0) + 1;
    }
    return [
      for (final o in orders)
        OrderSummary(
          order: o,
          customerName: names[o.customerId] ?? '',
          itemCount: counts[o.id] ?? 0,
        ),
    ];
  }

  Stream<List<OrderSummary>> watchSummaries() => watchTables(
        _db,
        [_db.orders, _db.orderItems, _db.debtors],
        loadSummaries,
      );

  Future<OrderDetails?> loadOrder(String id) async {
    final order = await (_db.select(_db.orders)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (order == null) return null;
    final items = await (_db.select(_db.orderItems)
          ..where((t) => t.orderId.equals(id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final history = await (_db.select(_db.orderStatusHistory)
          ..where((t) => t.orderId.equals(id) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final names = await _customerNames();
    return OrderDetails(
      order: order,
      customerName: names[order.customerId] ?? '',
      items: items,
      history: history,
    );
  }

  Stream<OrderDetails?> watchOrder(String id) => watchTables(
        _db,
        [_db.orders, _db.orderItems, _db.orderStatusHistory, _db.debtors],
        () => loadOrder(id),
      );

  /// Имена покупателей, включая удалённых из книги (старые заказы их помнят).
  Future<Map<String, String>> _customerNames() async {
    final rows = await _db.select(_db.debtors).get();
    return {for (final d in rows) d.id: d.name};
  }

  // ---------- создание и правка ----------

  /// Создаёт заказ в статусе «Создан».
  Future<String> createOrder({
    required String customerId,
    required List<OrderItemInput> items,
    required String actorName,
    String? comment,
  }) async {
    _validateItems(items);
    return _db.transaction(() async {
      final customer = await (_db.select(_db.debtors)
            ..where((t) => t.id.equals(customerId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (customer == null) {
        throw ArgumentError.value(customerId, 'customerId', 'Customer not found');
      }

      final maxNumber = await (_db.selectOnly(_db.orders)
            ..addColumns([_db.orders.number.max()]))
          .map((r) => r.read(_db.orders.number.max()))
          .getSingle();

      final order = await _db.into(_db.orders).insertReturning(
            OrdersCompanion.insert(
              number: (maxNumber ?? 0) + 1,
              customerId: customerId,
              status: OrderStatus.created,
              total: orderSum(items),
              comment: Value(_blankToNull(comment)),
            ),
          );
      await _insertItems(order.id, items);
      await _addHistory(order.id, OrderStatus.created, actorName);
      return order.id;
    });
  }

  /// Заменяет состав заказа (пока его можно менять) и пересчитывает сумму.
  Future<void> updateItems(
    String orderId,
    List<OrderItemInput> items, {
    required String actorName,
    String? comment,
  }) async {
    _validateItems(items);
    await _db.transaction(() async {
      final order = await _requireOrder(orderId);
      if (!canEditItems(order.status)) {
        throw StateError('Order in status ${order.status.name} cannot be edited');
      }
      final now = DateTime.now();
      await (_db.update(_db.orderItems)
            ..where((t) => t.orderId.equals(orderId) & t.deletedAt.isNull()))
          .write(OrderItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
      ));
      await _insertItems(orderId, items);
      await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
        OrdersCompanion(
          total: Value(orderSum(items)),
          comment: Value(_blankToNull(comment)),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _addHistory(orderId, order.status, actorName, isEdit: true);
    });
  }

  // ---------- статусы ----------

  /// Меняет статус по правилам [canTransition] и пишет историю.
  /// «Доставлен» ставится только через [deliver] (там фиксируется оплата и долг).
  Future<void> changeStatus(
    String orderId,
    OrderStatus to, {
    required String actorName,
    String? note,
  }) async {
    if (to == OrderStatus.delivered) {
      throw ArgumentError('Use deliver() to mark an order delivered');
    }
    await _db.transaction(() async {
      final order = await _requireOrder(orderId);
      if (!canTransition(order.status, to)) throw InvalidOrderTransition(order.status, to);
      await _setStatus(order, to, actorName, note: note);
    });
  }

  /// Отмечает доставку: сколько получено [paidAmount], остаток записывается
  /// долгом в книгу должников (один раз). Если оплачено полностью — долга нет.
  ///
  /// В книге появляются две операции, обе привязаны к заказу: «дал в долг» на
  /// всю сумму заказа и «получил оплату» на [paidAmount] (если он больше нуля).
  Future<void> deliver(
    String orderId, {
    required int paidAmount,
    required String actorName,
  }) async {
    await _db.transaction(() async {
      final order = await _requireOrder(orderId);
      if (!canTransition(order.status, OrderStatus.delivered)) {
        throw InvalidOrderTransition(order.status, OrderStatus.delivered);
      }
      if (paidAmount < 0 || paidAmount > order.total) {
        throw ArgumentError.value(paidAmount, 'paidAmount', 'Must be in 0..${order.total}');
      }

      await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
        OrdersCompanion(paidAmount: Value(paidAmount)),
      );
      await _setStatus(order, OrderStatus.delivered, actorName);

      if (paidAmount < order.total) {
        await _recordDebt(order, paidAmount);
      }
    });
  }

  Future<void> _recordDebt(Order order, int paidAmount) async {
    final already = await (_db.select(_db.debtTransactions)
          ..where((t) =>
              t.orderId.equals(order.id) &
              t.kind.equals(DebtKind.debt.index) &
              t.deletedAt.isNull()))
        .get();
    if (already.isNotEmpty) return; // долг по заказу уже записан

    final now = DateTime.now();
    final label = '#${order.number}';
    await _db.into(_db.debtTransactions).insert(
          DebtTransactionsCompanion.insert(
            debtorId: order.customerId,
            kind: DebtKind.debt,
            amount: order.total,
            occurredAt: now,
            comment: Value(label),
            orderId: Value(order.id),
          ),
        );
    if (paidAmount > 0) {
      await _db.into(_db.debtTransactions).insert(
            DebtTransactionsCompanion.insert(
              debtorId: order.customerId,
              kind: DebtKind.payment,
              amount: paidAmount,
              occurredAt: now,
              comment: Value(label),
              orderId: Value(order.id),
            ),
          );
    }
  }

  // ---------- внутреннее ----------

  Future<Order> _requireOrder(String id) async {
    final order = await (_db.select(_db.orders)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (order == null) throw StateError('Order $id not found');
    return order;
  }

  Future<void> _setStatus(Order order, OrderStatus to, String actorName, {String? note}) async {
    await (_db.update(_db.orders)..where((t) => t.id.equals(order.id))).write(
      OrdersCompanion(
        status: Value(to),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
    await _addHistory(order.id, to, actorName, note: note);
  }

  Future<void> _addHistory(
    String orderId,
    OrderStatus status,
    String actorName, {
    String? note,
    bool isEdit = false,
  }) =>
      _db.into(_db.orderStatusHistory).insert(
            OrderStatusHistoryCompanion.insert(
              orderId: orderId,
              status: status,
              actorName: actorName,
              note: Value(_blankToNull(note)),
              isEdit: Value(isEdit),
            ),
          );

  Future<void> _insertItems(String orderId, List<OrderItemInput> items) async {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      await _db.into(_db.orderItems).insert(
            OrderItemsCompanion.insert(
              orderId: orderId,
              productId: Value(item.productId),
              name: item.name,
              unit: item.unit,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              packSize: Value(item.packSize),
              packPrice: Value(item.packPrice),
              lineTotal: item.lineTotal,
              position: i,
            ),
          );
    }
  }

  void _validateItems(List<OrderItemInput> items) {
    if (items.isEmpty) throw ArgumentError.value(items, 'items', 'Order must have items');
    if (items.length > maxOrderItems) {
      throw ArgumentError.value(items.length, 'items', 'At most $maxOrderItems items');
    }
    for (final i in items) {
      if (i.quantity < 1 || i.quantity > maxItemQuantity) {
        throw ArgumentError.value(i.quantity, 'quantity', 'Must be in 1..$maxItemQuantity');
      }
      if (i.unitPrice <= 0 || i.unitPrice > maxAmount) {
        throw ArgumentError.value(i.unitPrice, 'unitPrice', 'Invalid price');
      }
      if (i.name.trim().isEmpty) throw ArgumentError.value(i.name, 'name', 'Empty name');
    }
    if (orderSum(items) > maxAmount) {
      throw ArgumentError.value(orderSum(items), 'total', 'Order total is too large');
    }
  }
}

String? _blankToNull(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
