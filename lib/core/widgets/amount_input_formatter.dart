import 'package:flutter/services.dart';

import '../utils/money.dart';

/// Оставляет только цифры и группирует по три: «1250000» → «1 250 000».
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final capped = digits.length > 12 ? digits.substring(0, 12) : digits;
    final text = formatAmount(int.parse(capped));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
