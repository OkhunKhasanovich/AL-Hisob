const shopNameMinLength = 2;
const shopNameMaxLength = 60;

/// Убирает крайние пробелы и схлопывает повторные внутри.
String normalizeShopName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Название валидно, если после нормализации длина 2…60 символов.
bool isValidShopName(String raw) {
  final length = normalizeShopName(raw).length;
  return length >= shopNameMinLength && length <= shopNameMaxLength;
}
