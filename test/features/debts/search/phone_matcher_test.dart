import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/debts/domain/search/phone_matcher.dart';

void main() {
  group('queryDigits', () {
    test('любые форматы дают национальные цифры', () {
      for (final q in ['+998 (90) 123-45-67', '998901234567', '+998901234567']) {
        expect(queryDigits(q), '901234567', reason: q);
      }
      expect(queryDigits('90 123 45 67'), '901234567');
      expect(queryDigits('(90)123'), '90123');
    });

    test('«+998», «998», «9», «99» и пустой запрос — без ограничения', () {
      for (final q in ['', '+998', '998', '99', '9', '+', 'abc']) {
        expect(queryDigits(q), '', reason: q);
      }
    });

    test('код страны с продолжением срезается, остальное — нет', () {
      expect(queryDigits('9989'), '9');
      expect(queryDigits('99890'), '90');
      expect(queryDigits('991'), '991', reason: 'это не код страны');
    });
  });

  test('localPart', () {
    expect(localPart('+998901234567'), '901234567');
    expect(localPart('901234567'), '901234567');
    expect(localPart('+79123456789'), '79123456789');
  });

  group('scorePhone', () {
    const local = '901234567';

    test('лестница оценок', () {
      expect(scorePhone('901234567', local), 1.0);
      expect(scorePhone('4567', local), 0.95); // конец
      expect(scorePhone('9012', local), 0.9); // начало
      expect(scorePhone('2345', local), 0.8); // середина
      expect(scorePhone('90', local), 0.5); // короткий префикс
    });

    test('нет совпадения', () {
      expect(scorePhone('999', local), 0);
      expect(scorePhone('9', '123456789'), 0);
      expect(scorePhone('23', local), 0, reason: 'короткие цифры — только префикс');
      expect(scorePhone('9012345678', local), 0, reason: 'длиннее номера');
      expect(scorePhone('', local), 0);
    });
  });
}
