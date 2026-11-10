/// Подготовка текста SMS и подсчёт сегментов (стоимости).
library;

/// Апострофы узбекской латиницы (‘ ’ ʻ ʼ ` ´) не входят в алфавит GSM-7, и из-за
/// одного такого знака вся SMS становится Unicode (70 символов вместо 160).
/// Заменяем их на обычный апостроф.
String normalizeSmsText(String text) => text
    .replaceAll(RegExp('[‘’ʻʼ`´′]'), "'")
    .replaceAll(RegExp('[“”«»]'), '"')
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .trim();

const _gsmBasic = '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?'
    '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';
const _gsmExtended = '^{}\\[~]|€\f';

final _basic = _gsmBasic.runes.toSet();
final _extended = _gsmExtended.runes.toSet();

class SmsLength {
  const SmsLength({required this.characters, required this.segments, required this.isUnicode});

  /// Длина в «единицах» кодировки (расширенные символы GSM считаются за 2).
  final int characters;
  final int segments;
  final bool isUnicode;
}

SmsLength smsLength(String text) {
  if (text.isEmpty) return const SmsLength(characters: 0, segments: 0, isUnicode: false);

  var units = 0;
  var gsm = true;
  for (final r in text.runes) {
    if (_basic.contains(r)) {
      units += 1;
    } else if (_extended.contains(r)) {
      units += 2;
    } else {
      gsm = false;
      break;
    }
  }

  if (gsm) {
    return SmsLength(
      characters: units,
      segments: units <= 160 ? 1 : (units / 153).ceil(),
      isUnicode: false,
    );
  }
  // Unicode: UTF-16, символы вне BMP занимают 2 единицы.
  final utf16 = text.length;
  return SmsLength(
    characters: utf16,
    segments: utf16 <= 70 ? 1 : (utf16 / 67).ceil(),
    isUnicode: true,
  );
}
