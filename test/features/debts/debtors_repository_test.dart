import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/database/sync_columns.dart';
import 'package:al_hisob/core/domain/debt_kind.dart';
import 'package:al_hisob/core/utils/money.dart';
import 'package:al_hisob/features/debts/data/debtors_repository.dart';

void main() {
  late AppDatabase db;
  late DebtorsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DebtorsRepository(db);
  });
  tearDown(() => db.close());

  Future<String> newDebtor({List<String> phones = const []}) =>
      repo.createDebtor(DebtorInput(name: 'Alisher', shopName: 'Baraka', phones: phones));

  group('должники', () {
    test('создание нормализует данные и телефоны', () async {
      final id = await repo.createDebtor(const DebtorInput(
        name: '  Sherzod   Aliyev ',
        shopName: ' Do‘kon ',
        address: '  ',
        note: null,
        phones: ['90 123-45-67', '+998 90 123 45 67', '', '998 91 765 43 21'],
      ));

      final d = (await repo.loadDetails(id))!.summary;
      expect(d.debtor.name, 'Sherzod Aliyev');
      expect(d.debtor.shopName, 'Do‘kon');
      expect(d.debtor.address, isNull, reason: 'пустая строка → null');
      expect(d.debtor.syncStatus, SyncStatus.pending);
      expect(d.debtor.id, hasLength(36));
      expect(d.phones, ['+998901234567', '+998917654321'], reason: 'дубликат схлопнут');
      expect(d.balance, 0);
    });

    test('невалидные данные отклоняются', () async {
      expect(() => repo.createDebtor(const DebtorInput(name: '   ')), throwsArgumentError);
      expect(() => repo.createDebtor(const DebtorInput(name: 'A', phones: ['123'])),
          throwsArgumentError);
      expect(await repo.loadSummaries(), isEmpty, reason: 'ничего не записалось');
    });

    test('редактирование: меняет поля, добавляет и убирает телефоны', () async {
      final id = await newDebtor(phones: ['901111111', '902222222']);
      final before = (await repo.loadDetails(id))!.summary.debtor;
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await repo.updateDebtor(
        id,
        const DebtorInput(
          name: 'Alisher Karimov',
          address: 'Chilonzor',
          phones: ['902222222', '903333333'],
        ),
      );

      final after = (await repo.loadDetails(id))!.summary;
      expect(after.debtor.name, 'Alisher Karimov');
      expect(after.debtor.shopName, isNull);
      expect(after.debtor.address, 'Chilonzor');
      expect(after.debtor.updatedAt.isAfter(before.updatedAt), isTrue);
      expect(after.phones, ['+998902222222', '+998903333333']);

      // Убранный телефон остался в БД как soft-deleted — для синхронизации.
      final all = await db.select(db.debtorPhones).get();
      final removed = all.singleWhere((p) => p.phone == '+998901111111');
      expect(removed.deletedAt, isNotNull);
      expect(removed.syncStatus, SyncStatus.pending);
    });

    test('удаление скрывает должника, его телефоны и операции (soft delete)', () async {
      final id = await newDebtor(phones: ['901111111']);
      await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 1000,
        occurredAt: DateTime(2026, 1, 1),
      );
      final other = await newDebtor();

      await repo.deleteDebtor(id);

      expect(await repo.loadDetails(id), isNull);
      expect((await repo.loadSummaries()).map((s) => s.debtor.id), [other]);
      expect(await db.select(db.debtors).get(), hasLength(2), reason: 'строки остались в БД');
      expect((await db.select(db.debtTransactions).get()).single.deletedAt, isNotNull);
      expect((await db.select(db.debtorPhones).get()).single.deletedAt, isNotNull);
    });
  });

  group('операции', () {
    test('баланс считается из операций', () async {
      final id = await newDebtor();
      Future<void> add(DebtKind k, int amount, DateTime at) => repo
          .addTransaction(debtorId: id, kind: k, amount: amount, occurredAt: at)
          .then((_) {});

      await add(DebtKind.debt, 2000000, DateTime(2026, 1, 10));
      await add(DebtKind.payment, 500000, DateTime(2026, 1, 20));
      await add(DebtKind.debt, 100000, DateTime(2026, 1, 15));

      final details = (await repo.loadDetails(id))!;
      expect(details.summary.balance, 1600000);
      expect(details.summary.lastOperationAt, DateTime(2026, 1, 20));
      expect(details.transactions.map((t) => t.amount), [500000, 100000, 2000000],
          reason: 'новые сверху');
    });

    test('комментарий и заказ сохраняются, пустой комментарий → null', () async {
      final id = await newDebtor();
      final withData = await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 10,
        occurredAt: DateTime(2026, 1, 1),
        comment: '  товар  ',
        orderId: 'order-1',
      );
      final blank = await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.payment,
        amount: 5,
        occurredAt: DateTime(2026, 1, 2),
        comment: '   ',
      );
      expect(withData.comment, 'товар');
      expect(withData.orderId, 'order-1');
      expect(blank.comment, isNull);
    });

    test('недопустимая сумма отклоняется', () async {
      final id = await newDebtor();
      for (final amount in [0, -5, 1000000000000]) {
        expect(
          () => repo.addTransaction(
              debtorId: id, kind: DebtKind.debt, amount: amount, occurredAt: DateTime.now()),
          throwsArgumentError,
          reason: '$amount',
        );
      }
    });

    test('удаление операции пересчитывает баланс', () async {
      final id = await newDebtor();
      final tx = await repo.addTransaction(
          debtorId: id, kind: DebtKind.debt, amount: 700, occurredAt: DateTime(2026, 1, 1));
      await repo.addTransaction(
          debtorId: id, kind: DebtKind.payment, amount: 200, occurredAt: DateTime(2026, 1, 2));
      expect((await repo.loadDetails(id))!.summary.balance, 500);

      await repo.deleteTransaction(tx.id);

      final details = (await repo.loadDetails(id))!;
      expect(details.summary.balance, -200);
      expect(details.transactions, hasLength(1));
      final row = (await db.select(db.debtTransactions).get()).singleWhere((t) => t.id == tx.id);
      expect(row.deletedAt, isNotNull);
    });

    test('БД не принимает нулевую сумму (check constraint)', () async {
      final id = await newDebtor();
      expect(
        () => db.into(db.debtTransactions).insert(DebtTransactionsCompanion.insert(
              debtorId: id,
              kind: DebtKind.debt,
              amount: 0,
              occurredAt: DateTime.now(),
              comment: const Value(null),
            )),
        throwsA(anything),
      );
    });
  });

  group('потоки', () {
    test('watchSummaries обновляется при изменениях', () async {
      final events = <List<String>>[];
      final sub = repo.watchSummaries().listen(
            (list) => events.add(list.map((s) => '${s.debtor.name}:${s.balance}').toList()),
          );
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final id = await newDebtor();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.addTransaction(
          debtorId: id, kind: DebtKind.debt, amount: 300, occurredAt: DateTime(2026, 1, 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.first, isEmpty);
      expect(events.last, ['Alisher:300']);
    });

    test('watchDetails сообщает об удалении должника', () async {
      final id = await newDebtor();
      final events = <DebtorDetails?>[];
      final sub = repo.watchDetails(id).listen(events.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await repo.deleteDebtor(id);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.first, isNotNull);
      expect(events.last, isNull);
    });
  });

  group('текущий долг при создании должника', () {
    test('становится операцией «долг» и попадает в баланс', () async {
      final id = await repo.createDebtor(const DebtorInput(
        name: 'Alisher',
        initialDebt: 2500000,
        initialDebtComment: 'Из тетради',
      ));
      final details = (await repo.loadDetails(id))!;
      expect(details.summary.balance, 2500000);
      expect(details.transactions, hasLength(1));
      final t = details.transactions.single;
      expect([t.kind, t.amount, t.comment], [DebtKind.debt, 2500000, 'Из тетради']);
      expect(details.summary.lastOperationAt, isNotNull);
    });

    test('без долга операций нет', () async {
      final id = await repo.createDebtor(const DebtorInput(name: 'Bobur'));
      expect((await repo.loadDetails(id))!.transactions, isEmpty);
    });

    test('недопустимая сумма отклоняется, должник не создаётся', () async {
      expect(() => repo.createDebtor(const DebtorInput(name: 'X', initialDebt: -5)),
          throwsArgumentError);
      expect(() => repo.createDebtor(DebtorInput(name: 'X', initialDebt: maxAmount + 1)),
          throwsArgumentError);
      expect(await repo.loadSummaries(), isEmpty);
    });

    test('при редактировании долг не добавляется заново', () async {
      final id = await repo.createDebtor(const DebtorInput(name: 'A', initialDebt: 1000));
      await repo.updateDebtor(id, const DebtorInput(name: 'A2', initialDebt: 9999));
      expect((await repo.loadDetails(id))!.summary.balance, 1000);
    });
  });
}
