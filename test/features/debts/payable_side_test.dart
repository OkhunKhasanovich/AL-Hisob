import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/app.dart';
import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/debt_direction.dart';
import 'package:al_hisob/core/domain/debt_kind.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/core/settings/settings_repository.dart';
import 'package:al_hisob/features/debts/data/debtors_repository.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openDebts(WidgetTester tester, {AppSettingsSnapshot? settings}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider
            .overrideWithValue(settings ?? const AppSettingsSnapshot(locale: Locale('ru'))),
      ],
      child: const AlHisobApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
  }

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      await ShopProfileRepository(db).create(name: 'Shop', roles: {ShopRole.buyer});
      final repo = DebtorsRepository(db);
      await repo.createDebtor(const DebtorInput(name: 'Buyer Ali', initialDebt: 5000));
      await repo.createDebtor(
        const DebtorInput(name: 'Supplier Baraka', initialDebt: 9000, direction: DebtDirection.payable),
      );
    });
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  final toggle = find.byTooltip('Мои долги поставщикам');

  testWidgets('в шапке переключатель вместо динамика; нажатие открывает «Я должен» и обратно', (tester) async {
    await seed(tester);
    await openDebts(tester);

    expect(find.byTooltip('Массовая рассылка'), findsNothing, reason: 'рассылка перенесена в «Ещё»');
    expect(find.byIcon(Icons.campaign_rounded), findsNothing);
    expect(find.text('Долги'), findsWidgets);
    expect(find.text('Buyer Ali'), findsOneWidget);
    expect(find.text('Supplier Baraka'), findsNothing, reason: 'поставщик — в другой книге');
    expect(find.text('Вам должны'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    expect(find.text('Я должен'), findsWidgets, reason: 'заголовок сменился');
    expect(find.text('Supplier Baraka'), findsOneWidget);
    expect(find.text('Buyer Ali'), findsNothing);
    expect(find.text('Вы должны'), findsOneWidget, reason: 'подпись карточки сменилась');
    expect(find.textContaining('9 000'), findsWidgets, reason: 'итог — только долги поставщикам');
    expect(find.byTooltip('Мне должны'), findsOneWidget, reason: 'значок теперь возвращает обратно');
    expect(find.byTooltip('Добавить поставщика'), findsOneWidget);

    await tester.tap(find.byTooltip('Мне должны'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(find.text('Buyer Ali'), findsOneWidget);
    expect(find.text('Supplier Baraka'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('итоги раздельные: 5 000 у должников и 9 000 у поставщиков не складываются', (tester) async {
    await seed(tester);
    await openDebts(tester);
    expect(find.textContaining('5 000 сум'), findsWidgets);
    expect(find.textContaining('14 000'), findsNothing);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(find.textContaining('9 000 сум'), findsWidgets);
    expect(find.textContaining('14 000'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('выбранная книга запоминается между запусками', (tester) async {
    await seed(tester);
    await openDebts(tester);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    final saved = await tester.runAsync(() => SettingsRepository(db).load());
    expect(saved!.debtsSide, DebtDirection.payable);
    await closeApp(tester);

    await openDebts(
      tester,
      settings: AppSettingsSnapshot(locale: const Locale('ru'), debtsSide: saved.debtsSide),
    );
    expect(find.text('Supplier Baraka'), findsOneWidget);
    expect(find.text('Я должен'), findsWidgets);
    await closeApp(tester);
  });

  testWidgets('у поставщика свои подписи кнопок, а SMS-напоминания нет', (tester) async {
    await seed(tester);
    await openDebts(tester);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    await tester.tap(find.text('Supplier Baraka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    expect(find.text('Взял в долг'), findsOneWidget);
    expect(find.text('Оплатил'), findsOneWidget);
    expect(find.text('SMS-напоминание'), findsNothing, reason: 'поставщикам SMS не отправляем');
    await closeApp(tester);
  });

  testWidgets('новый поставщик создаётся в книге «Я должен», а не среди должников', (tester) async {
    await seed(tester);
    await openDebts(tester);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    await tester.tap(find.byTooltip('Добавить поставщика'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Новый поставщик'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Optom Plus');
    await tester.pump();
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Сохранить'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.debtors).get());
    expect(rows!.singleWhere((r) => r.name == 'Optom Plus').direction, DebtDirection.payable);
    await closeApp(tester);
  });

  testWidgets('оплата поставщику тоже не больше долга; у каждого поставщика свой предел', (tester) async {
    await seed(tester);
    final id = (await tester.runAsync(() => db.select(db.debtors).get()))!
        .singleWhere((d) => d.name == 'Supplier Baraka')
        .id;
    final repo = DebtorsRepository(db);
    final error = await tester.runAsync(() async {
      try {
        await repo.addTransaction(
            debtorId: id, kind: DebtKind.payment, amount: 9001, occurredAt: DateTime.now());
        return null;
      } on PaymentExceedsDebtException catch (e) {
        return e;
      }
    });
    expect(error, isA<PaymentExceedsDebtException>());
    expect(error!.balance, 9000);
    await tester.runAsync(() => repo.addTransaction(
        debtorId: id, kind: DebtKind.payment, amount: 9000, occurredAt: DateTime.now()));
    final details = await tester.runAsync(() => repo.loadDetails(id));
    expect(details!.summary.balance, 0);
    await closeApp(tester);
  });

  testWidgets('в «Ещё» есть «Массовая рассылка»', (tester) async {
    await seed(tester);
    await openDebts(tester);
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Массовая рассылка'), findsOneWidget);
    await closeApp(tester);
  });
}
