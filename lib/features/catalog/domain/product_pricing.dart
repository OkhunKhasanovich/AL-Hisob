import '../../../core/database/app_database.dart';

/// Упаковка задана целиком (вид, размер и цена).
bool hasPack(Product p) => p.packKind != null && p.packSize != null && p.packPrice != null;

/// Цена одной единицы при покупке упаковкой.
double? packUnitPrice(Product p) =>
    hasPack(p) ? p.packPrice! / p.packSize! : null;

/// Скидка за покупку упаковкой в процентах от цены «поштучно», целое число.
/// `null` — упаковки нет или она не дешевле.
int? packDiscountPercent(Product p) {
  if (!hasPack(p)) return null;
  final full = p.packSize! * p.unitPrice;
  if (full <= 0 || p.packPrice! >= full) return null;
  return ((full - p.packPrice!) * 100 / full).round();
}

/// Стоимость [quantity] единиц: сначала целые упаковки по цене упаковки,
/// остаток — по цене за единицу. Упаковка учитывается, только если заданы
/// и [packSize], и [packPrice].
int lineTotal({
  required int unitPrice,
  required int quantity,
  int? packSize,
  int? packPrice,
}) {
  if (quantity <= 0) return 0;
  if (packSize == null || packPrice == null || packSize <= 0) return quantity * unitPrice;
  final packs = quantity ~/ packSize;
  final rest = quantity % packSize;
  return packs * packPrice + rest * unitPrice;
}

/// То же для товара каталога.
int orderTotal(Product p, int quantity) => lineTotal(
      unitPrice: p.unitPrice,
      quantity: quantity,
      packSize: hasPack(p) ? p.packSize : null,
      packPrice: hasPack(p) ? p.packPrice : null,
    );

/// Сколько целых упаковок и сколько штук сверху в [quantity] единиц.
({int packs, int rest}) packBreakdown(int quantity, int? packSize) {
  if (packSize == null || packSize <= 0) return (packs: 0, rest: quantity);
  return (packs: quantity ~/ packSize, rest: quantity % packSize);
}

/// Объём заказа не меньше минимальной партии.
bool meetsMinOrder(Product p, int quantity) => quantity >= p.minOrderQuantity;
