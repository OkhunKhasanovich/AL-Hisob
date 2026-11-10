import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/sms/domain/sms_text.dart';

void main() {
  group('normalizeSmsText', () {
    test('узбекские апострофы → обычный', () {
      expect(normalizeSmsText('to‘lang, o’zbek, g`ishtli, sa´at, oʻ'),
          "to'lang, o'zbek, g'ishtli, sa'at, o'");
    });

    test('кавычки и тире', () {
      expect(normalizeSmsText('«Baraka» — “shop”'), '"Baraka" - "shop"');
    });

    test('обрезает пробелы по краям', () {
      expect(normalizeSmsText('  hi \n'), 'hi');
    });

    test('после нормализации латиница с апострофом остаётся GSM-7', () {
      expect(smsLength('to‘lang').isUnicode, isTrue);
      expect(smsLength(normalizeSmsText('to‘lang')).isUnicode, isFalse);
    });
  });

  group('smsLength', () {
    test('пустой текст', () {
      final l = smsLength('');
      expect([l.characters, l.segments], [0, 0]);
    });

    test('латиница: 160 символов — один сегмент, 161 — два', () {
      expect(smsLength('a' * 160).segments, 1);
      expect(smsLength('a' * 161).segments, 2);
      expect(smsLength('a' * 306).segments, 2);
      expect(smsLength('a' * 307).segments, 3);
      expect(smsLength('a' * 160).isUnicode, isFalse);
    });

    test('кириллица — Unicode: 70 / 71 символ', () {
      final l = smsLength('я' * 70);
      expect(l.isUnicode, isTrue);
      expect(l.segments, 1);
      expect(smsLength('я' * 71).segments, 2);
      expect(smsLength('я' * 134).segments, 2);
      expect(smsLength('я' * 135).segments, 3);
    });

    test('один не-GSM символ переводит всё сообщение в Unicode', () {
      expect(smsLength('${'a' * 100}ў').isUnicode, isTrue);
      expect(smsLength('${'a' * 100}ў').segments, 2);
    });

    test('расширенные символы GSM считаются за два', () {
      final l = smsLength('{}[]');
      expect(l.characters, 8);
      expect(l.isUnicode, isFalse);
      expect(smsLength('€' * 80).segments, 1);
      expect(smsLength('€' * 81).segments, 2);
    });

    test('цифры, пробелы и знаки — GSM-7', () {
      expect(smsLength('Qarz: 1 500 000 so\'m, 13.11.2026!').isUnicode, isFalse);
    });
  });
}
