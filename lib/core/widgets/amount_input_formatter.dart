import 'package:flutter/services.dart';

import '../utils/money.dart';

/// Оставляет только цифры и группирует по три: «1250000» → «1 250 000».
/// Если задан [max], число больше него заменяется на [max]: больше ввести нельзя.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({this.max});

  final int? max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final capped = digits.length > 12 ? digits.substring(0, 12) : digits;
    var value = int.parse(capped);
    final limit = max;
    if (limit != null && value > limit) value = limit;
    if (value <= 0 && limit != null) return const TextEditingValue();
    final text = formatAmount(value);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
