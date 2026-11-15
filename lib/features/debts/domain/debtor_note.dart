import '../../../core/database/app_database.dart';

/// Заметка должника одной строкой: то, что вписано в «Заметку», и (у старых записей) название
/// магазина, которое раньше хранилось отдельным полем. Поле «Магазин» убрано: оно слилось с заметкой.
/// `null`, если ничего нет.
String? debtorNote(Debtor d) {
  final parts = <String>[];
  for (final raw in [d.note, d.shopName]) {
    final t = raw?.trim();
    if (t != null && t.isNotEmpty && !parts.contains(t)) parts.add(t);
  }
  return parts.isEmpty ? null : parts.join(' • ');
}
