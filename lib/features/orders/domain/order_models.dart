import '../../../core/database/app_database.dart';
import '../../../core/domain/product_unit.dart';
import '../../catalog/domain/product_pricing.dart';

/// Позиция заказа при создании/правке.
class OrderItemInput {
  const OrderItemInput({
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    this.productId,
    this.packSize,
    this.packPrice,
  });

  /// Берёт название, единицу и цены из товара каталога (снимок на момент заказа).
  factory OrderItemInput.fromProduct(Product p, int quantity) => OrderItemInput(
        productId: p.id,
        name: p.name,
        unit: p.unit,
        quantity: quantity,
        unitPrice: p.unitPrice,
        packSize: hasPack(p) ? p.packSize : null,
        packPrice: hasPack(p) ? p.packPrice : null,
      );

  final String? productId;
  final String name;
  final ProductUnit unit;
  final int quantity;
  final int unitPrice;
  final int? packSize;
  final int? packPrice;

  int get lineTotal => lineTotalOf(this);

  OrderItemInput withQuantity(int q) => OrderItemInput(
        productId: productId,
        name: name,
        unit: unit,
        quantity: q,
        unitPrice: unitPrice,
        packSize: packSize,
        packPrice: packPrice,
      );
}

int lineTotalOf(OrderItemInput i) => lineTotal(
      unitPrice: i.unitPrice,
      quantity: i.quantity,
      packSize: i.packSize,
      packPrice: i.packPrice,
    );

/// Сумма заказа.
int orderSum(Iterable<OrderItemInput> items) => items.fold(0, (sum, i) => sum + i.lineTotal);

/// Строка списка заказов.
class OrderSummary {
  const OrderSummary({required this.order, required this.customerName, required this.itemCount});

  final Order order;
  final String customerName;
  final int itemCount;
}

/// Полная карточка заказа.
class OrderDetails {
  const OrderDetails({
    required this.order,
    required this.customerName,
    required this.items,
    required this.history,
  });

  final Order order;
  final String customerName;

  /// По порядку добавления.
  final List<OrderItem> items;

  /// От старых к новым.
  final List<OrderStatusHistoryData> history;

  /// Сколько осталось получить с покупателя.
  int get remaining => order.total - order.paidAmount;
}
