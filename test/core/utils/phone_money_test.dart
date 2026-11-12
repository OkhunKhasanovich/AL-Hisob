import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/utils/money.dart';
import 'package:al_hisob/core/utils/phone.dart';

void main() {
  group('normalizePhone', () {
    test('разные форматы дают один результат', () {
      const expected = '+998901234567';
      for (final raw in [
        '901234567',
        '90 123 45 67',
        '90-123-45-67',
        '998901234567',
        '+998901234567',
        '+998 (90) 123 45 67',
        ' 998 90 123-45-67 ',
      ]) {
        expect(normalizePhone(raw), expected, reason: raw);
      }
    });

    test('мусор и неверная длина отклоняются', () {
      for (final raw in ['', 'abc', '12345', '9012345678', '+7 912 345 67 89', '99890123456']) {
        expect(normalizePhone(raw), isNull, reason: raw);
        expect(isValidPhone(raw), isFalse);
      }
    });

    test('formatPhone', () {
      expect(formatPhone('+998901234567'), '+998 90 123 45 67');
      expect(formatPhone('+79123456789'), '+79123456789');
    });
  });

  group('деньги', () {
    test('formatAmount', () {
      expect(formatAmount(0), '0');
      expect(formatAmount(999), '999');
      expect(formatAmount(1000), '1 000');
      expect(formatAmount(1250000), '1 250 000');
      expect(formatAmount(-50000), '-50 000');
    });

    test('parseAmount', () {
      expect(parseAmount('1 250 000'), 1250000);
      expect(parseAmount('  500 '), 500);
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('1' * 13), isNull);
    });

    test('formatDate', () {
      expect(formatDate(DateTime(2026, 3, 5)), '05.03.2026');
    });
  });
}
