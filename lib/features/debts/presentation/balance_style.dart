import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';

/// Долг — акцентным «тревожным» цветом, ноль и переплата — спокойным.
Color balanceColor(ColorScheme scheme, int balance) =>
    balance > 0 ? scheme.error : scheme.primary;

/// Короткая подпись баланса для списка: сумма, «Нет долга» или «Переплата …».
String balanceText(AppLocalizations l10n, int balance) {
  if (balance > 0) return '${formatAmount(balance)} ${l10n.currencySum}';
  if (balance == 0) return l10n.noDebt;
  return '${l10n.overpaid} ${formatAmount(-balance)} ${l10n.currencySum}';
}
