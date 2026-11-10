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
/// остаток — по цене за единицу.
int orderTotal(Product p, int quantity) {
  if (quantity <= 0) return 0;
  if (!hasPack(p)) return quantity * p.unitPrice;
  final packs = quantity ~/ p.packSize!;
  final rest = quantity % p.packSize!;
  return packs * p.packPrice! + rest * p.unitPrice;
}

/// Объём заказа не меньше минимальной партии.
bool meetsMinOrder(Product p, int quantity) => quantity >= p.minOrderQuantity;
