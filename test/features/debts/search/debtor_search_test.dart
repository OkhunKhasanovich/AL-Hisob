import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/database/sync_columns.dart';
import 'package:al_savdogar/features/debts/domain/debt_summary.dart';
import 'package:al_savdogar/features/debts/domain/search/debtor_search.dart';

final _t = DateTime(2026, 1, 1);

DebtorSummary person(
  String name, {
  String? shop,
  List<String> phones = const [],
  int balance = 0,
}) =>
    DebtorSummary(
      debtor: Debtor(
        id: name,
        createdAt: _t,
        updatedAt: _t,
        syncStatus: SyncStatus.pending,
        name: name,
        shopName: shop,
      ),
      phones: phones,
      balance: balance,
      lastOperationAt: null,
    );

void main() {
  final ahmad = person('Ahmad Karimov',
      shop: 'Baraka', phones: ['+998901234567'], balance: 500000);
  final sherzodRu = person('Шерзод Алиев', phones: ['+998935551122'], balance: 100000);
  final sherzodLat = person('Sherzod Usmonov', shop: 'Do‘kon Oq Yo‘l');
  final otkir = person('O‘tkir Rahimov', phones: ['+998977001122', '+998712345678']);
  final qodir = person('Қодир Назаров', phones: ['+998991112233']);
  final alisher = person('Alisher Navoiy');
  final bobur = person('Bobur Mirzo');
  final dilshod = person('Dilshod');
  final anvar = person('Anvar Bek');

  final all = [ahmad, sherzodRu, sherzodLat, otkir, qodir, alisher, bobur, dilshod, anvar];
  final index = DebtorSearchIndex(all);

  List<String> found(String query) => index.search(query).map((h) => h.summary.debtor.name).toList();

  group('имя: транслитерация', () {
    test('точное имя и фамилия', () => expect(found('Ahmad Karimov').first, 'Ahmad Karimov'));

    for (final q in ['Axmad', 'Ахмад', 'akhmad', 'AHMAD', 'ahmad']) {
      test('«$q» находит Ahmad Karimov', () => expect(found(q), ['Ahmad Karimov']));
    }

    test('Sherzod находит и латиницу, и кириллицу', () {
      expect(found('Sherzod'), unorderedEquals(['Шерзод Алиев', 'Sherzod Usmonov']));
    });

    test('Шерзод находит оба написания', () {
      expect(found('Шерзод'), unorderedEquals(['Шерзод Алиев', 'Sherzod Usmonov']));
    });

    for (final q in ['Ўткир', "O'tkir", 'Oʻtkir', 'O`tkir', 'otkir', 'o‘tqir']) {
      test('«$q» находит O‘tkir', () => expect(found(q), ['O‘tkir Rahimov']));
    }

    for (final q in ['Qodir', 'Kodir', 'кодир', 'Қодир']) {
      test('«$q» находит Қодир', () => expect(found(q), ['Қодир Назаров']));
    }

    test('фамилия кириллицей находит латиницу и наоборот', () {
      expect(found('Каримов'), ['Ahmad Karimov']);
      expect(found('Usmonov'), ['Sherzod Usmonov']);
      expect(found('Nazarov'), ['Қодир Назаров']);
    });

    test('порядок слов не важен', () {
      expect(found('Karimov Ahmad'), ['Ahmad Karimov']);
      expect(found('Алиев Шерзод'), ['Шерзод Алиев']);
    });

    test('дефис в запросе = пробел', () => expect(found('Anvar-bek'), ['Anvar Bek']));
  });

  group('имя: опечатки', () {
    test('перестановка букв', () {
      expect(found('Alisehr'), ['Alisher Navoiy']);
      expect(found('Shrezod'), unorderedEquals(['Шерзод Алиев', 'Sherzod Usmonov']));
    });

    test('пропущенная буква', () {
      expect(found('Dilshd'), ['Dilshod']);
      expect(found('Qodr'), ['Қодир Назаров']);
    });

    test('лишняя буква', () => expect(found('Boburr'), ['Bobur Mirzo']));

    test('замена буквы', () {
      expect(found('Bobir'), ['Bobur Mirzo']);
      expect(found('Utkir'), ['O‘tkir Rahimov']);
    });

    test('голосовые/глухие и гласные: Sherzot, Karemov', () {
      expect(found('Sherzot'), unorderedEquals(['Шерзод Алиев', 'Sherzod Usmonov']));
      expect(found('Karemov'), ['Ahmad Karimov']);
    });

    test('две опечатки допустимы только в длинных словах', () {
      final long = DebtorSearchIndex([person('Muhammadjon Aliyev')]);
      expect(long.search('Muhamedjan'), hasLength(1));
      expect(found('Karemav'), isEmpty, reason: '7 букв, две опечатки');
    });

    test('похожие фамилии разных людей не путаются', () {
      expect(found('Karimov'), ['Ahmad Karimov']);
      expect(found('Rahimov'), ['O‘tkir Rahimov']);
    });

    test('опечатка в начале слова при наборе («по мере ввода»)', () {
      expect(found('Alishe'), ['Alisher Navoiy']);
      expect(found('Dilsho'), ['Dilshod']);
    });
  });

  group('имя: поиск по мере набора', () {
    test('префикс', () {
      expect(found('Sherz'), unorderedEquals(['Шерзод Алиев', 'Sherzod Usmonov']));
      expect(found('Kar'), ['Ahmad Karimov']);
    });

    test('«Sher» также находит Alisher (по части слова), но он ниже', () {
      final names = found('Sher');
      expect(names.take(2), unorderedEquals(['Шерзод Алиев', 'Sherzod Usmonov']));
      expect(names.last, 'Alisher Navoiy');
    });

    test('одна буква — имена и фамилии на неё', () {
      expect(found('A'), containsAll(['Ahmad Karimov', 'Alisher Navoiy', 'Шерзод Алиев', 'Anvar Bek']));
      expect(found('A'), isNot(contains('Bobur Mirzo')));
    });

    test('каждое следующее слово сужает выдачу', () {
      expect(found('Sherzod'), hasLength(2));
      expect(found('Sherzod Us'), ['Sherzod Usmonov']);
    });

    test('слово внутри другого слова (от 3 букв)', () {
      expect(found('mad'), ['Ahmad Karimov']);
    });
  });

  group('нет ложных совпадений', () {
    test('несуществующее имя', () {
      expect(found('Davron'), isEmpty);
      expect(found('xyzxyz'), isEmpty);
    });

    test('короткое слово без опечаток', () {
      expect(found('Ola'), isEmpty);
      expect(found('Abu'), isEmpty);
    });

    test('все слова запроса обязаны найтись', () {
      expect(found('Ahmad Usmonov'), isEmpty);
      expect(found('Bobur Karimov'), isEmpty);
    });
  });

  group('магазин', () {
    test('поиск по названию магазина', () {
      expect(found('Baraka'), ['Ahmad Karimov']);
      expect(found('oq yol'), ['Sherzod Usmonov']);
    });

    test('имя весомее магазина', () {
      final list = DebtorSearchIndex([
        person('Zafar', shop: 'Baraka'),
        person('Baraka Aliev'),
      ]).search('Baraka');
      expect(list.map((h) => h.summary.debtor.name), ['Baraka Aliev', 'Zafar']);
    });
  });

  group('телефон', () {
    for (final q in [
      '901234567',
      '90 123 45 67',
      '+998901234567',
      '998901234567',
      '+998 (90) 123-45-67',
      '90-123-45-67',
    ]) {
      test('формат «$q»', () => expect(found(q), ['Ahmad Karimov']));
    }

    test('по последним цифрам; номер, оканчивающийся на них, выше «содержащего»', () {
      final hits = index.search('4567');
      expect(hits.first.summary.debtor.name, 'Ahmad Karimov');
      expect(hits.map((h) => h.summary.debtor.name), contains('O‘tkir Rahimov'));
    });

    test('по любой части номера', () {
      expect(found('3456'), unorderedEquals(['Ahmad Karimov', 'O‘tkir Rahimov']));
      expect(found('555'), ['Шерзод Алиев']);
    });

    test('короткий префикс из 2 цифр — начало номера', () {
      expect(found('93'), ['Шерзод Алиев']);
      expect(found('97'), ['O‘tkir Rahimov']);
    });

    test('несколько телефонов у одного должника', () {
      expect(found('712345678'), ['O‘tkir Rahimov']);
      expect(found('977001122'), ['O‘tkir Rahimov']);
    });

    test('matchedPhone — тот номер, по которому нашли', () {
      expect(index.search('712345').single.matchedPhone, '+998712345678');
      expect(index.search('977001').single.matchedPhone, '+998977001122');
    });

    test('без цифр в запросе matchedPhone пуст', () {
      expect(index.search('Ahmad').single.matchedPhone, isNull);
    });

    test('нет такого номера', () {
      expect(found('000000'), isEmpty);
      expect(found('+998 99 999 99 99'), isEmpty);
    });

    test('имя и номер в одном запросе', () {
      expect(found('Sherzod 93'), ['Шерзод Алиев']);
      expect(found('Ahmad 4567'), ['Ahmad Karimov']);
      expect(found('Ahmad 555'), isEmpty);
    });

    test('номер длиннее реального не совпадает', () {
      expect(found('9012345678'), isEmpty);
    });
  });

  group('пустой и служебный ввод', () {
    test('пустой запрос возвращает всех в исходном порядке', () {
      expect(found(''), all.map((s) => s.debtor.name).toList());
      expect(found('   '), all.map((s) => s.debtor.name).toList());
      expect(found('..'), all.map((s) => s.debtor.name).toList());
    });

    test('«+998» и «998» — это ещё не запрос по номеру', () {
      expect(found('+998'), hasLength(all.length));
      expect(found('998'), hasLength(all.length));
    });

    test('пустой список', () {
      expect(searchDebtors(const [], 'Ahmad'), isEmpty);
    });
  });

  group('релевантность', () {
    DebtorSearchIndex build(List<DebtorSummary> l) => DebtorSearchIndex(l);
    List<String> names(List<SearchHit> h) => h.map((e) => e.summary.debtor.name).toList();

    test('точное > начало слова > опечатка', () {
      final hits = build([
        person('Alishir'),
        person('Alisherov'),
        person('Alisher'),
      ]).search('Alisher');
      expect(names(hits), ['Alisher', 'Alisherov', 'Alishir']);
      expect(hits[0].score, greaterThan(hits[1].score));
      expect(hits[1].score, greaterThan(hits[2].score));
    });

    test('полное совпадение имени и фамилии выше частичного', () {
      final hits = build([
        person('Ahmad Rahimov'),
        person('Ahmad Karimov'),
        person('Karim Ahmadov'),
      ]).search('Ahmad Karimov');
      expect(names(hits).first, 'Ahmad Karimov');
    });

    test('при равной релевантности — у кого больше долг, затем по имени', () {
      final hits = build([
        person('Sardor B', balance: 100),
        person('Sardor A', balance: 100),
        person('Sardor C', balance: 900),
      ]).search('Sardor');
      expect(names(hits), ['Sardor C', 'Sardor A', 'Sardor B']);
    });

    test('кириллица и латиница одного имени оцениваются одинаково', () {
      final hits = index.search('Sherzod');
      expect(hits[0].score, hits[1].score);
    });
  });

  test('вход не мутируется, индекс можно использовать повторно', () {
    final copy = List.of(all);
    index.search('Ahmad');
    index.search('Sherzod');
    expect(all, copy);
    expect(index.length, all.length);
    expect(found('Ahmad'), ['Ahmad Karimov']);
  });

  test('скорость: 5000 должников, 20 запросов', () {
    final big = [
      for (var i = 0; i < 5000; i++)
        person('Name$i Surname${i * 7}', shop: 'Shop $i', phones: ['+99890${(1000000 + i).toString()}'])
    ];
    final bigIndex = DebtorSearchIndex(big);
    final sw = Stopwatch()..start();
    for (final q in ['Name12', 'Surnam', '9090', 'Nmae44', 'Shop 7', '+998 90 100', 'sur', 'x', '1234', 'name99 sur']) {
      bigIndex.search(q);
      bigIndex.search('$q ');
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(5000), reason: '${sw.elapsedMilliseconds} мс');
  });
}
