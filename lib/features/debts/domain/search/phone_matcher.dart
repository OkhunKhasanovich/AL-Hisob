/// Поиск по номеру: запрос — любая часть номера в любом формате.
library;

const _countryCode = '998';

/// Только цифры.
String digitsOf(String input) => input.replaceAll(RegExp(r'\D'), '');

/// Национальная часть номера без кода страны: `+998901234567` → `901234567`.
String localPart(String phone) {
  final d = digitsOf(phone);
  return d.startsWith(_countryCode) && d.length > _countryCode.length
      ? d.substring(_countryCode.length)
      : d;
}

/// Цифры запроса без кода страны. Пустая строка — ограничения по номеру нет
/// (запрос без цифр либо только «+998»).
String queryDigits(String query) {
  final d = digitsOf(query);
  if (d.length > _countryCode.length && d.startsWith(_countryCode)) {
    return d.substring(_countryCode.length);
  }
  if (_countryCode.startsWith(d)) return ''; // «9», «99», «998» — это начало кода страны
  return d;
}

/// Оценка совпадения цифр запроса [q] с национальной частью номера [local]:
/// 1.0 — номер целиком; 0.95 — конец номера (по последним цифрам ищут чаще
/// всего); 0.9 — начало; 0.8 — любая часть; 0.5 — короткий (1–2 цифры) префикс.
double scorePhone(String q, String local) {
  if (q.isEmpty || local.isEmpty || q.length > local.length) return 0;
  if (q == local) return 1.0;
  if (q.length < 3) return local.startsWith(q) ? 0.5 : 0;
  if (local.endsWith(q)) return 0.95;
  if (local.startsWith(q)) return 0.9;
  if (local.contains(q)) return 0.8;
  return 0;
}
