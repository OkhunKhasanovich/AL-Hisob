import 'sms_template.dart';
import 'sms_text.dart';

/// Готовый текст напоминания: шаблон → подстановка → нормализация апострофов.
String buildReminderText({
  required String template,
  required String language,
  required String debtorName,
  required int amount,
  required String shopName,
  required DateTime dueDate,
}) {
  final rendered = renderSmsTemplate(
    template,
    SmsTemplateValues(name: debtorName, amount: amount, shop: shopName, date: dueDate),
    language,
  );
  return normalizeSmsText(rendered);
}

/// Срок оплаты по умолчанию — через 3 дня.
DateTime defaultDueDate(DateTime now) {
  final d = now.add(const Duration(days: 3));
  return DateTime(d.year, d.month, d.day);
}
