import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/debts/domain/search/text_normalizer.dart';

void main() {
  /// Все написания должны давать один ключ.
  void sameKey(List<String> variants, {String? expected}) {
    final keys = variants.map(toSearchKey).toSet();
    expect(keys, hasLength(1), reason: 'разные ключи: ${{for (final v in variants) v: toSearchKey(v)}}');
    if (expected != null) expect(keys.single, expected);
  }

  group('транслитерация: одно имя — один ключ', () {
    test('Ахмад = Axmad = Ahmad = Akhmad', () {
      sameKey(['Ахмад', 'Axmad', 'Ahmad', 'Akhmad', 'AHMAD', 'ахмад'], expected: 'ahmad');
    });

    test('Шерзод = Sherzod', () {
      sameKey(['Шерзод', 'Sherzod', 'SHERZOD', 'шерзод'], expected: 'Serzod');
    });

    test('o‘ / ў: Ўткир = O‘tkir = O\'tkir = Oʻtkir = O`tkir', () {
      sameKey(['Ўткир', 'O‘tkir', "O'tkir", 'Oʻtkir', 'O`tkir', 'O’tkir', 'Otkir'],
          expected: 'otkir');
    });

    test('g‘ / ғ: Ғаффор = G‘affor = Gaffor', () {
      sameKey(['Ғаффор', 'G‘affor', "G'affor", 'Gaffor'], expected: 'gafor');
    });

    test('q / қ / k: Қодир = Qodir = Kodir', () {
      sameKey(['Қодир', 'Qodir', 'Kodir', 'кодир'], expected: 'kodir');
    });

    test('x / х / h / kh: Ҳасан = Хасан = Xasan = Hasan', () {
      sameKey(['Ҳасан', 'Хасан', 'Xasan', 'Hasan', 'Khasan'], expected: 'hasan');
    });

    test('sh / ш и ch / ч', () {
      sameKey(['Шариф', 'Sharif'], expected: 'Sarif');
      sameKey(['Чингиз', 'Chingiz'], expected: 'Cingiz');
      sameKey(['Шамсиддин', 'Shamsiddin'], expected: 'Samsidin');
    });

    test('j / ж / dj', () {
      sameKey(['Жамшид', 'Jamshid', 'Djamshid'], expected: 'jamSid');
    });

    test('ю, я, ё: Юсуф = Yusuf, Ёқуб = Yoqub', () {
      sameKey(['Юсуф', 'Yusuf'], expected: 'yusuf');
      sameKey(['Ёқуб', 'Yoqub'], expected: 'yokub');
      expect(toSearchKey('Яков'), 'yakov');
    });

    test('«Ye» в начале слова: Эргаш = Ergash = Yergash', () {
      sameKey(['Эргаш', 'Ergash', 'Yergash'], expected: 'ergaS');
    });

    test('двойные согласные схлопываются: Muhammad = Muhamad', () {
      sameKey(['Muhammad', 'Muhamad', 'Мухаммад'], expected: 'muhamad');
    });

    test('w → v, ц → s', () {
      expect(toSearchKey('Wali'), toSearchKey('Vali'));
      expect(toSearchKey('Цой'), toSearchKey('Soy'));
    });
  });

  group('чистка строки', () {
    test('регистр и лишние пробелы', () {
      expect(toSearchKey('  ALISHER   Karimov '), 'aliSer karimov');
    });

    test('дефис и знаки препинания разделяют слова', () {
      expect(toSearchKey('Anvar-bek'), 'anvar bek');
      expect(toSearchKey('Do‘kon "Baraka", №1'), 'dokon baraka 1');
    });

    test('смесь кириллицы и латиницы в одной строке', () {
      expect(toSearchKey('Али Karimov'), 'ali karimov');
    });

    test('пустой ввод', () {
      expect(toSearchKey(''), '');
      expect(toSearchKey('  ...  '), '');
      expect(searchTokens('  '), isEmpty);
    });

    test('токены', () {
      expect(searchTokens('Шерзод Алиев'), ['Serzod', 'aliev']);
    });
  });
}
