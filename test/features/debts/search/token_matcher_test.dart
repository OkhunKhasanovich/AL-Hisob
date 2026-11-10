import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/debts/domain/search/token_matcher.dart';

void main() {
  test('допустимое число опечаток растёт с длиной слова', () {
    expect(maxTypos(1), 0);
    expect(maxTypos(3), 0);
    expect(maxTypos(4), 1);
    expect(maxTypos(7), 1);
    expect(maxTypos(8), 2);
    expect(maxTypos(12), 2);
  });

  test('точное совпадение — максимум', () => expect(scoreToken('ahmad', 'ahmad'), 1.0));

  test('префикс: чем больше набрано, тем выше оценка', () {
    final short = scoreToken('ah', 'ahmad');
    final long = scoreToken('ahma', 'ahmad');
    expect(short, greaterThan(0.85));
    expect(long, greaterThan(short));
    expect(long, lessThan(1.0));
  });

  test('опечатки в целом слове', () {
    expect(scoreToken('ahmed', 'ahmad'), greaterThan(0.7)); // замена
    expect(scoreToken('ahmd', 'ahmad'), greaterThan(0.7)); // пропуск
    expect(scoreToken('ahmmad', 'ahmad'), greaterThan(0.7)); // лишняя
    expect(scoreToken('amhad', 'ahmad'), greaterThan(0.7)); // перестановка
  });

  test('перестановка внутри «sh»/«ch» — одна опечатка', () {
    expect(scoreToken('alisehr', 'aliSer'), greaterThan(0.7)); // alisher
    expect(scoreToken('hcoriev', 'Coriev'), greaterThan(0.7)); // choriev
  });

  test('опечатка в уже набранном начале длинного слова', () {
    final s = scoreToken('alishr', 'alisherov');
    expect(s, greaterThan(0.5));
    expect(s, lessThan(0.7));
  });

  test('короткие слова не исправляются', () {
    expect(scoreToken('ali', 'ola'), 0);
    expect(scoreToken('abu', 'abd'), 0);
    expect(scoreToken('ali', 'ali'), 1.0);
    expect(scoreToken('al', 'ali'), greaterThan(0.85), reason: 'но префикс работает');
  });

  test('подстрока внутри слова — слабое совпадение, от 3 символов', () {
    expect(scoreToken('mad', 'ahmad'), 0.55);
    expect(scoreToken('ma', 'ahmad'), 0);
  });

  test('похожие фамилии разных людей не склеиваются', () {
    expect(scoreToken('karimov', 'rahimov'), 0);
    expect(scoreToken('karimov', 'karimova'), greaterThan(0.85), reason: 'префикс');
  });

  test('слишком много опечаток — нет совпадения', () {
    expect(scoreToken('ahmad', 'davron'), 0);
    expect(scoreToken('bobur', 'dilshod'), 0);
  });

  test('лестница: точное > префикс > опечатка > подстрока', () {
    final exact = scoreToken('sherzod', 'sherzod');
    final prefix = scoreToken('sherz', 'sherzod');
    final typo = scoreToken('sherzot', 'sherzod');
    final inside = scoreToken('erzod', 'sherzod');
    expect(exact, greaterThan(prefix));
    expect(prefix, greaterThan(typo));
    expect(typo, greaterThan(inside));
    expect(inside, greaterThan(0));
  });

  test('пустые строки', () {
    expect(scoreToken('', 'ahmad'), 0);
    expect(scoreToken('ahmad', ''), 0);
  });
}
