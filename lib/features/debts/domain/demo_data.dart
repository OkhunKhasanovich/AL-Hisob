import 'dart:math';

import '../../../core/domain/debt_kind.dart';

/// Пометка, по которой тестовых должников можно найти и удалить.
const demoDebtorNote = 'Тестовый должник';

/// Одна операция тестового должника.
class DemoOperation {
  const DemoOperation(this.kind, this.amount, this.daysAgo, this.hour);

  final DebtKind kind;
  final int amount;

  /// Сколько календарных дней назад (0 — сегодня).
  final int daysAgo;
  final int hour;
}

/// Тестовый должник целиком: данные и история операций (от старых к новым).
class DemoDebtor {
  const DemoDebtor({
    required this.name,
    required this.shopName,
    required this.address,
    required this.phone,
    required this.operations,
  });

  final String name;
  final String shopName;
  final String address;
  final String phone;
  final List<DemoOperation> operations;
}

const _firstNames = [
  'Alisher',
  'Bobur',
  'Dilshod',
  'Farhod',
  'Gulnora',
  'Hasan',
  'Ibrohim',
  'Jasur',
  'Kamola',
  'Laziz',
  'Malika',
  'Nodir',
  'Otabek',
  'Parviz',
  'Rustam',
  'Sardor',
  'Timur',
  'Umid',
  'Zafar',
  'Shahzod',
  'Nigora',
  'Sherzod',
  'Aziz',
  'Madina',
  'Behzod',
  'Азиз',
  'Бахтиёр',
  'Дильноза',
  'Ойбек',
  'Санжар',
];

const _lastNames = [
  'Karimov',
  'Rahimov',
  'Tursunov',
  'Yusupov',
  'Abdullayev',
  'Ismoilov',
  'Mirzayev',
  'Nazarov',
  'Qodirov',
  'Sobirov',
  'Xolmatov',
  'Ergashev',
  'Hamidov',
  'Normatov',
  'Ahmedov',
  'Saidov',
  'Omonov',
  'Jalolov',
  'Rasulov',
  'Toshmatov',
  'Каримов',
  'Рахимов',
  'Юсупов',
  'Хамидов',
];

const _shops = [
  'Baraka market',
  'Do‘stlik',
  'Navro‘z',
  'Oltin vodiy',
  'Sharq do‘koni',
  'Oila market',
  'Yulduz',
  'Bahor',
  'Chorsu savdo',
  'Ziyo',
  'Mevazor',
  'Orzu',
  'Fayz',
  'Samarqand non',
  'Magnit',
  'Тандыр',
  'Универмаг №3',
  'Нур',
];

const _streets = [
  'Navoiy',
  'Amir Temur',
  'Mustaqillik',
  'Bobur',
  'Alisher Navoiy',
  'Oybek',
  'Chilonzor',
  'Yunusobod',
  'Mirzo Ulug‘bek',
  'Shota Rustaveli',
];

/// Строит [count] правдоподобных тестовых должников. Один и тот же [random]
/// (с тем же зерном) даёт один и тот же результат.
///
/// В истории есть и свежие операции (последние дни), и «забытые» должники без движений
/// больше месяца, и полностью расплатившиеся — чтобы проверить фильтры, поиск и график.
/// Оплата никогда не превышает текущий долг, поэтому переплат нет.
List<DemoDebtor> generateDemoDebtors(int count, Random random) {
  final phones = <String>{};
  final names = <String>{};

  String phone() {
    while (true) {
      final code = const ['90', '91', '93', '94', '95', '97', '99', '33', '88'][random.nextInt(9)];
      final p = '$code${1000000 + random.nextInt(9000000)}';
      if (phones.add(p)) return p;
    }
  }

  String name() {
    for (var i = 0; i < 20; i++) {
      final n =
          '${_firstNames[random.nextInt(_firstNames.length)]} '
          '${_lastNames[random.nextInt(_lastNames.length)]}';
      if (names.add(n)) return n;
    }
    final n =
        '${_firstNames[random.nextInt(_firstNames.length)]} '
        '${_lastNames[random.nextInt(_lastNames.length)]} ${names.length + 1}';
    names.add(n);
    return n;
  }

  int roundedAmount(int min, int max) => (min + random.nextInt(max - min + 1)) ~/ 10000 * 10000;

  return [
    for (var i = 0; i < count; i++)
      () {
        // ~20% — старые долги (последняя операция > 30 дней назад), остальные — свежее.
        final stale = random.nextInt(100) < 20;
        final oldest = stale ? 45 + random.nextInt(80) : 8 + random.nextInt(60);
        final newest = stale ? 31 + random.nextInt(max(1, oldest - 31)) : random.nextInt(7);
        final opCount = 1 + random.nextInt(5);

        final days = <int>[
          oldest,
          for (var k = 1; k < opCount; k++) newest + random.nextInt(max(1, oldest - newest + 1)),
        ]..sort((a, b) => b.compareTo(a)); // от старых к новым

        final ops = <DemoOperation>[];
        var balance = 0;
        for (var k = 0; k < days.length; k++) {
          final canPay = balance >= 10000;
          final pay = k > 0 && canPay && random.nextInt(100) < 40;
          if (pay) {
            // Оплата — от 20% до 100% текущего долга, не больше него.
            final part = (balance * (20 + random.nextInt(81)) / 100).round() ~/ 10000 * 10000;
            final amount = part.clamp(10000, balance);
            ops.add(DemoOperation(DebtKind.payment, amount, days[k], 9 + random.nextInt(9)));
            balance -= amount;
          } else {
            final amount = roundedAmount(50000, 6000000);
            ops.add(DemoOperation(DebtKind.debt, amount, days[k], 9 + random.nextInt(9)));
            balance += amount;
          }
        }

        return DemoDebtor(
          name: name(),
          shopName: _shops[random.nextInt(_shops.length)],
          address: '${_streets[random.nextInt(_streets.length)]} ${1 + random.nextInt(120)}',
          phone: phone(),
          operations: ops,
        );
      }(),
  ];
}
