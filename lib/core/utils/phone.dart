/// Нормализация и показ узбекских номеров.
///
/// Принимает «90 123-45-67», «+998 (90) 123 45 67», «998901234567» и т.п.
/// Возвращает `+998901234567` или `null`, если номер не похож на узбекский
/// мобильный/городской (9 цифр без кода страны либо 12 цифр с 998).
String? normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 9) return '+998$digits';
  if (digits.length == 12 && digits.startsWith('998')) return '+$digits';
  return null;
}

bool isValidPhone(String raw) => normalizePhone(raw) != null;

/// `+998901234567` → `+998 90 123 45 67`. Неузнанный формат возвращается как есть.
String formatPhone(String normalized) {
  final m = RegExp(r'^\+998(\d{2})(\d{3})(\d{2})(\d{2})$').firstMatch(normalized);
  if (m == null) return normalized;
  return '+998 ${m[1]} ${m[2]} ${m[3]} ${m[4]}';
}
