import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/domain/debt_kind.dart';
import 'package:al_savdogar/core/l10n/l10n.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/utils/phone.dart';
import 'package:al_savdogar/features/debts/data/debtors_repository.dart';
import 'package:al_savdogar/features/debts/domain/debt_filter.dart';
import 'package:al_savdogar/features/debts/domain/debt_trend.dart';
import 'package:al_savdogar/features/debts/domain/demo_data.dart';
import 'package:al_savdogar/features/debts/presentation/demo_data_section.dart';

void main() {
  group('generateDemoDebtors', () {
    test('нужное число, уникальные имена и валидные уникальные телефоны', () {
      final list = generateDemoDebtors(50, Random(1));
      expect(list.length, 50);
      expect(list.map((d) => d.name).toSet().length, 50);
      expect(list.map((d) => d.phone).toSet().length, 50);
      for (final d in list) {
        expect(normalizePhone(d.phone), isNotNull, reason: d.phone);
        expect(d.operations, isNotEmpty);
      }
    });

    test('одно зерно — одни данные', () {
      String dump(int seed) => generateDemoDebtors(10, Random(seed))
          .map((d) => '${d.name}|${d.phone}|${d.operations.map((o) => '${o.kind}${o.amount}@${o.daysAgo}').join(',')}')
          .join(';');
      expect(dump(7), dump(7));
      expect(dump(7), isNot(dump(8)));
    });

    test('оплата не больше долга, операции идут от старых к новым, суммы допустимы', () {
      for (final d in generateDemoDebtors(200, Random(3))) {
        var balance = 0;
        var prevDays = 1 << 30;
        for (final o in d.operations) {
          expect(o.daysAgo, lessThanOrEqualTo(prevDays));
          prevDays = o.daysAgo;
          expect(o.amount, greaterThan(0));
          balance += o.kind == DebtKind.debt ? o.amount : -o.amount;
          expect(balance, greaterThanOrEqualTo(0), reason: 'переплаты быть не должно');
        }
        expect(d.operations.first.kind, DebtKind.debt);
      }
    });

    test('есть и свежие, и забытые должники', () {
      final list = generateDemoDebtors(50, Random(5));
      int last(DemoDebtor d) => d.operations.last.daysAgo;
      expect(list.where((d) => last(d) > 30), isNotEmpty);
      expect(list.where((d) => last(d) <= 7), isNotEmpty);
    });
  });

  group('репозиторий', () {
    late AppDatabase db;
    late DebtorsRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DebtorsRepository(db);
    });
    tearDown(() => db.close());

    test('добавляет 50 должников с операциями и пометкой', () async {
      final now = DateTime(2026, 6, 30, 12);
      expect(await repo.seedDemoDebtors(now: now, random: Random(1)), 50);
      final all = await repo.loadSummaries();
      expect(all.length, 50);
      expect(all.every((s) => s.debtor.note == demoDebtorNote), isTrue);
      expect(all.every((s) => s.phones.length == 1 && s.operationCount > 0), isTrue);
      expect(all.every((s) => s.balance >= 0), isTrue);
      expect(await repo.countDemoDebtors(), 50);

      // Недельный график строится и согласован с общим долгом.
      final txs = await repo.loadActiveTransactions();
      final trend = computeDebtTrend(txs, now: now);
      expect(trend.days, 7);
      expect(trend.last, totalOwed(all));
      expect(trend.isEmpty, isFalse);
    });

    test('удаляет только тестовых, настоящие остаются', () async {
      final mine = await repo.createDebtor(const DebtorInput(name: 'Real Person', note: 'мой клиент'));
      await repo.seedDemoDebtors(count: 10, random: Random(2));
      expect((await repo.loadSummaries()).length, 11);

      expect(await repo.deleteDemoDebtors(), 10);
      final left = await repo.loadSummaries();
      expect(left.map((s) => s.debtor.id), [mine]);
      expect(await repo.countDemoDebtors(), 0);
      expect(await repo.loadActiveTransactions(), isEmpty);
      expect(await repo.deleteDemoDebtors(), 0, reason: 'повтор безопасен');
    });
  });

  group('кнопки в «Ещё»', () {
    testWidgets('добавить, затем удалить с подтверждением', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: const Scaffold(body: SingleChildScrollView(child: DemoDataSection())),
        ),
      ));

      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      await tester.tap(find.text('Добавить 50 тестовых должников'));
      await settle();
      expect(find.text('Добавлено: 50'), findsOneWidget);
      expect(await tester.runAsync(() => DebtorsRepository(db).countDemoDebtors()), 50);

      await tester.tap(find.text('Удалить тестовых должников'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Удалить тестовых должников?'), findsOneWidget);
      await tester.tap(find.text('Удалить'));
      await settle();
      expect(find.text('Удалено: 50'), findsOneWidget);
      expect(await tester.runAsync(() => DebtorsRepository(db).countDemoDebtors()), 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  });
}
