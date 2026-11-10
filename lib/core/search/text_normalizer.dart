/// Приведение имён к «ключу поиска»: разные написания одного и того же
/// имени (кириллица, узбекская латиница, русская транслитерация) дают один
/// и тот же или очень близкий ключ.
///
/// Внутренние символы ключа: `S` = sh/ш, `C` = ch/ч (заглавные, чтобы не
/// пересекаться с обычными буквами: вход всегда приводится к нижнему регистру).
library;

const _cyrillic = <String, String>{
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
  'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'h', 'ц': 's', 'ч': 'C', 'ш': 'S', 'щ': 'S', 'ъ': '',
  'ы': 'i', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  // Узбекские буквы кириллицы.
  'ў': 'o', 'қ': 'k', 'ғ': 'g', 'ҳ': 'h',
  // Каракалпакские / прочие близкие.
  'ә': 'a', 'ө': 'o', 'ү': 'u', 'ң': 'n', 'ӣ': 'i', 'ҷ': 'j',
};

/// Диакритика латиницы → базовая буква.
const _latinAccents = <String, String>{
  'ö': 'o', 'ü': 'u', 'ä': 'a', 'ñ': 'n', 'é': 'e', 'è': 'e', 'ê': 'e',
  'á': 'a', 'à': 'a', 'ó': 'o', 'ò': 'o', 'í': 'i', 'ì': 'i', 'ú': 'u',
  'ù': 'u', 'ı': 'i', 'ş': 'S', 'ç': 'C', 'ğ': 'g', 'ń': 'n', 'ǵ': 'g',
  'ś': 's', 'ź': 'z', 'ž': 'j', 'š': 'S', 'č': 'C',
};

/// Апострофы и «турецкие запятые» узбекской латиницы: o‘, g‘, o', oʻ ...
final _apostrophes = RegExp('[\'`´‘’ʻʼʽ′ʹ"“”]');
final _combiningMarks = RegExp(r'[̀-ͯ]');
final _nonKeyChars = RegExp(r'[^a-zSC0-9 ]');
final _repeats = RegExp(r'(.)\1+');

/// Полный ключ строки: токены, разделённые пробелом.
String toSearchKey(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(_combiningMarks, '');
  s = s.replaceAll(_apostrophes, '');

  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_cyrillic[ch] ?? _latinAccents[ch] ?? ch);
  }
  s = buffer.toString();

  // Многобуквенные сочетания латиницы → одна буква ключа.
  s = s
      .replaceAll('shch', 'S')
      .replaceAll('sch', 'S')
      .replaceAll('sh', 'S')
      .replaceAll('ch', 'C')
      .replaceAll('kh', 'h')
      .replaceAll('zh', 'j')
      .replaceAll('dzh', 'j')
      .replaceAll('dj', 'j')
      .replaceAll('ts', 's');

  // Латинская «c» в заимствованных словах: перед e/i/y — «с» (Cement),
  // иначе «к» (Coca-Cola). «ch» уже заменено на `C` выше.
  s = s.replaceAllMapped(RegExp(r'c(?=[eiy])'), (_) => 's').replaceAll('c', 'k');

  // Одиночные буквы с разным написанием.
  s = s
      .replaceAll('q', 'k')
      .replaceAll('x', 'h')
      .replaceAll('w', 'v');

  // «Ye» в начале слова пишут и читают как «e» (Yergash = Ergash).
  s = s.replaceAllMapped(RegExp(r'(^|\s)ye'), (m) => '${m[1]}e');

  s = s.replaceAll(RegExp(r'[-_.,/\\]+'), ' ');
  s = s.replaceAll(_nonKeyChars, '');
  s = s.replaceAllMapped(_repeats, (m) => m[1]!);
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Токены ключа (слова).
List<String> searchTokens(String input) {
  final key = toSearchKey(input);
  return key.isEmpty ? const [] : key.split(' ');
}
