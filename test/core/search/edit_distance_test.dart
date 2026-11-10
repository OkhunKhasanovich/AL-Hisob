import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/search/edit_distance.dart';

void main() {
  group('damerauLevenshtein', () {
    test('равные строки', () => expect(damerauLevenshtein('ahmad', 'ahmad'), 0));

    test('пустые строки', () {
      expect(damerauLevenshtein('', ''), 0);
      expect(damerauLevenshtein('', 'abc'), 3);
      expect(damerauLevenshtein('abc', ''), 3);
    });

    test('вставка, удаление, замена — по 1', () {
      expect(damerauLevenshtein('ahmad', 'ahmmad'), 1);
      expect(damerauLevenshtein('ahmad', 'ahmd'), 1);
      expect(damerauLevenshtein('ahmad', 'ahmed'), 1);
    });

    test('перестановка соседних букв — 1', () {
      expect(damerauLevenshtein('ab', 'ba'), 1);
      expect(damerauLevenshtein('alisher', 'alisehr'), 1);
      expect(damerauLevenshtein('sherzod', 'shrezod'), 1);
    });

    test('классический пример kitten → sitting = 3', () {
      expect(damerauLevenshtein('kitten', 'sitting'), 3);
    });

    test('симметричность', () {
      expect(damerauLevenshtein('bobur', 'bubur'), damerauLevenshtein('bubur', 'bobur'));
      expect(damerauLevenshtein('abcdef', 'azced'), damerauLevenshtein('azced', 'abcdef'));
    });

    test('limit: точное значение, пока в пределах, иначе limit + 1', () {
      expect(damerauLevenshtein('ahmad', 'ahmed', limit: 1), 1);
      expect(damerauLevenshtein('ahmad', 'zzzzz', limit: 2), 3);
      expect(damerauLevenshtein('a', 'abcdefgh', limit: 2), 3, reason: 'разница длин больше limit');
    });
  });
}
