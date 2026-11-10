/// Суммы хранятся целыми сумами (UZS).
const maxAmount = 999999999999; // < 1 трлн

/// `1250000` → `1 250 000` (обычный пробел-разделитель, знак сохраняется).
String formatAmount(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

/// Достаёт целое число из строки ввода («1 250 000» → 1250000).
/// Пустая строка или нецифры → `null`.
int? parseAmount(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty || digits.length > 12) return null;
  return int.parse(digits);
}

/// `dd.MM.yyyy` без зависимости от локальных данных intl (kaa в intl нет).
String formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}';
}
