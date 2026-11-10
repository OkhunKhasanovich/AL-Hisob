import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/sms/domain/sms_template.dart';
import 'package:al_savdogar/features/sms/domain/sms_text.dart';

void main() {
  final values = SmsTemplateValues(
    name: 'Alisher',
    amount: 1500000,
    shop: 'Baraka Trade',
    date: DateTime(2026, 11, 13),
  );

  group('подстановка переменных', () {
    test('все четыре переменные по ТЗ', () {
      expect(
        renderSmsTemplate('{имя} / {сумма} / {магазин} / {дата}', values, 'ru'),
        'Alisher / 1 500 000 сум / Baraka Trade / 13.11.2026',
      );
    });

    test('синонимы на других языках', () {
      expect(renderSmsTemplate('{name} {amount} {shop} {date}', values, 'en'),
          'Alisher 1 500 000 UZS Baraka Trade 13.11.2026');
      expect(renderSmsTemplate('{ism} {summa} {dokon} {sana}', values, 'uz'),
          "Alisher 1 500 000 so'm Baraka Trade 13.11.2026");
      expect(renderSmsTemplate('{ati} {summa} {sane}', values, 'kaa'),
          'Alisher 1 500 000 swm 13.11.2026');
    });

    test('регистр и пробелы внутри скобок не важны', () {
      expect(renderSmsTemplate('{ ИМЯ } {Name}', values, 'ru'), 'Alisher Alisher');
    });

    test('переменная может повторяться', () {
      expect(renderSmsTemplate('{имя}, {имя}!', values, 'ru'), 'Alisher, Alisher!');
    });

    test('неизвестные переменные остаются в тексте', () {
      expect(renderSmsTemplate('Hi {foo} {имя}', values, 'ru'), 'Hi {foo} Alisher');
      expect(unknownPlaceholders('Hi {foo} {имя} {bar}'), ['{foo}', '{bar}']);
    });

    test('текст без переменных не меняется', () {
      expect(renderSmsTemplate('Просто текст', values, 'ru'), 'Просто текст');
    });

    test('валюта по языку шаблона', () {
      for (final lang in smsLanguages) {
        final out = renderSmsTemplate('{summa}{сумма}', values, lang);
        expect(out, contains(smsCurrency[lang]!), reason: lang);
      }
    });

    test('значение с фигурными скобками не подставляется повторно', () {
      final tricky = SmsTemplateValues(
          name: '{сумма}', amount: 5, shop: 'S', date: DateTime(2026, 1, 1));
      expect(renderSmsTemplate('{имя}', tricky, 'ru'), '{сумма}');
    });
  });

  group('шаблоны по умолчанию', () {
    test('есть для всех четырёх языков', () {
      expect(defaultSmsTemplates.keys, unorderedEquals(smsLanguages));
    });

    for (final lang in smsLanguages) {
      test('[$lang] все переменные распознаются и подставляются', () {
        final template = defaultSmsTemplates[lang]!;
        expect(unknownPlaceholders(template), isEmpty);

        final out = renderSmsTemplate(template, values, lang);
        expect(out, isNot(contains('{')));
        expect(out, contains('Alisher'));
        expect(out, contains('1 500 000'));
        expect(out, contains('Baraka Trade'));
        expect(out, contains('13.11.2026'));
      });

      test('[$lang] не длиннее 3 SMS-сегментов', () {
        final out = renderSmsTemplate(defaultSmsTemplates[lang]!, values, lang);
        expect(smsLength(normalizeSmsText(out)).segments, lessThanOrEqualTo(3));
      });
    }

    test('латинские шаблоны (uz, en) помещаются в GSM-7', () {
      for (final lang in ['uz', 'en']) {
        final out = normalizeSmsText(renderSmsTemplate(defaultSmsTemplates[lang]!, values, lang));
        expect(smsLength(out).isUnicode, isFalse, reason: lang);
      }
    });
  });

  test('SmsVariable.byAlias', () {
    expect(SmsVariable.byAlias('Сумма'), SmsVariable.amount);
    expect(SmsVariable.byAlias(' dokon '), SmsVariable.shop);
    expect(SmsVariable.byAlias('xyz'), isNull);
    expect(SmsVariable.name.primary, 'имя');
  });
}
