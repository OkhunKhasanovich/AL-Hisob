import '../../../core/utils/money.dart';

/// Языки шаблонов (совпадают с языками приложения).
const smsLanguages = ['uz', 'ru', 'en', 'kaa'];

/// Переменные шаблона. В тексте пишутся в фигурных скобках; у каждой есть
/// основное имя (по ТЗ — русское) и синонимы, чтобы шаблон на узбекском или
/// английском не приходилось набирать кириллицей.
enum SmsVariable {
  name(['имя', 'name', 'ism', 'ati', 'atı']),
  amount(['сумма', 'amount', 'summa']),
  shop(['магазин', 'shop', 'dokon', 'do‘kon', 'dukan', 'dúkan']),
  date(['дата', 'date', 'sana', 'sane', 'sáne']);

  const SmsVariable(this.aliases);

  final List<String> aliases;

  /// Основное имя переменной — первое в списке.
  String get primary => aliases.first;

  static SmsVariable? byAlias(String raw) {
    final key = raw.trim().toLowerCase();
    for (final v in values) {
      if (v.aliases.contains(key)) return v;
    }
    return null;
  }
}

/// Шаблоны по умолчанию. Имена переменных — на языке самого шаблона.
const defaultSmsTemplates = <String, String>{
  'ru': 'Здравствуйте, {имя}! Напоминаем о задолженности {сумма} перед {магазин}. '
      'Просим оплатить до {дата}. Спасибо!',
  'uz': "Assalomu alaykum, {ism}! {dokon} oldidagi {summa} qarzingiz haqida eslatamiz. "
      "Iltimos, {sana} gacha to'lang. Rahmat!",
  'en': 'Hello, {name}! A reminder about your balance of {amount} with {shop}. '
      'Please pay by {date}. Thank you!',
  'kaa': "Assalawma aleykum, {ati}! {dokon} aldındaǵı {summa} qarızıńız haqqında eskertemiz. "
      "Iltimas, {sane} ge shekem tólep qoyıń. Raxmet!",
};

/// Название денежной единицы на языке шаблона.
const smsCurrency = <String, String>{
  'ru': 'сум',
  'uz': "so'm",
  'en': 'UZS',
  'kaa': 'swm',
};

/// Данные для подстановки.
class SmsTemplateValues {
  const SmsTemplateValues({
    required this.name,
    required this.amount,
    required this.shop,
    required this.date,
  });

  final String name;

  /// Сумма долга в сумах.
  final int amount;

  /// Название вашего магазина (из профиля).
  final String shop;

  /// Срок оплаты.
  final DateTime date;
}

final _placeholder = RegExp(r'\{([^{}]+)\}');

/// Подставляет значения. Неизвестные `{слова}` остаются как есть, чтобы
/// опечатка в шаблоне была видна в предпросмотре, а не молча пропадала.
String renderSmsTemplate(String template, SmsTemplateValues values, String language) {
  final currency = smsCurrency[language] ?? smsCurrency['en']!;
  return template.replaceAllMapped(_placeholder, (m) {
    final variable = SmsVariable.byAlias(m[1]!);
    return switch (variable) {
      SmsVariable.name => values.name,
      SmsVariable.amount => '${formatAmount(values.amount)} $currency',
      SmsVariable.shop => values.shop,
      SmsVariable.date => formatDate(values.date),
      null => m[0]!,
    };
  });
}

/// Неизвестные переменные в шаблоне (для предупреждения при редактировании).
List<String> unknownPlaceholders(String template) => [
      for (final m in _placeholder.allMatches(template))
        if (SmsVariable.byAlias(m[1]!) == null) m[0]!,
    ];

/// Как называется переменная в шаблоне на данном языке (то, что вставляет кнопка
/// «Вставить переменную»). Совпадает с именами в [defaultSmsTemplates].
const smsVariableTags = <String, Map<SmsVariable, String>>{
  'ru': {SmsVariable.name: 'имя', SmsVariable.amount: 'сумма', SmsVariable.shop: 'магазин', SmsVariable.date: 'дата'},
  'uz': {SmsVariable.name: 'ism', SmsVariable.amount: 'summa', SmsVariable.shop: 'dokon', SmsVariable.date: 'sana'},
  'en': {SmsVariable.name: 'name', SmsVariable.amount: 'amount', SmsVariable.shop: 'shop', SmsVariable.date: 'date'},
  'kaa': {SmsVariable.name: 'ati', SmsVariable.amount: 'summa', SmsVariable.shop: 'dokon', SmsVariable.date: 'sane'},
};

String variableTag(String language, SmsVariable variable) =>
    '{${smsVariableTags[language]?[variable] ?? variable.primary}}';
