import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/app.dart';
import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/domain/debt_kind.dart';
import 'package:al_savdogar/core/domain/shop_role.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';
import 'package:al_savdogar/features/debts/data/debtors_repository.dart';
import 'package:al_savdogar/features/debts/presentation/transaction_sheet.dart';
import 'package:al_savdogar/features/profile/shop_profile_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Даёт реальным async-операциям БД завершиться и прокручивает кадры.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openDebts(WidgetTester tester) async {
    await tester.runAsync(
      () => ShopProfileRepository(db).create(name: 'Shop', roles: {ShopRole.wholesaler}),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider
            .overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
      ],
      child: const AlSavdogarApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> tapAsync(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
  }

  testWidgets('пустая книга → создание должника → операции → баланс и фильтры', (tester) async {
    await openDebts(tester);

    // Пустое состояние.
    expect(find.text('Пока нет должников'), findsOneWidget);

    // Создаём должника.
    await tester.tap(find.text('Добавить должника'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alisher');
    await tester.enterText(fields.at(2), '90 123 45 67');
    await tester.pump();
    await tapAsync(tester, find.text('Сохранить'));

    // Открылась карточка: имя, телефон, нулевой баланс.
    expect(find.text('Alisher'), findsWidgets);
    expect(find.text('+998 90 123 45 67'), findsOneWidget);
    expect(find.text('Нет долга'), findsOneWidget);
    expect(find.text('Операций пока нет'), findsOneWidget);

    // «Дал в долг» 1 500 000.
    await tester.tap(find.text('Дал в долг'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).first, '1500000');
    await tester.pump();
    expect(find.text('1 500 000'), findsOneWidget, reason: 'сумма группируется при вводе');
    await tapAsync(
      tester,
      find.descendant(of: find.byType(TransactionForm), matching: find.byType(FilledButton)),
    );
    expect(find.text('1 500 000 сум'), findsOneWidget);
    expect(find.text('+1 500 000'), findsOneWidget);

    // «Получил оплату» 500 000.
    await tester.tap(find.text('Получил оплату'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).first, '500000');
    await tester.pump();
    await tapAsync(
      tester,
      find.descendant(of: find.byType(TransactionForm), matching: find.byType(FilledButton)),
    );
    expect(find.text('1 000 000 сум'), findsOneWidget);
    expect(find.text('−500 000'), findsOneWidget);

    // Назад в список: должник и итог.
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(find.text('Alisher'), findsOneWidget);
    expect(find.text('1 000 000 сум'), findsNWidgets(2), reason: 'в итоге и в строке');

    // Фильтры: долг = порогу крупного (1 000 000) → виден; просроченных нет.
    await tester.tap(find.text('Крупные'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alisher'), findsOneWidget);
    await tester.tap(find.text('Просроченные'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alisher'), findsNothing);
    expect(find.text('По этому фильтру никого нет'), findsOneWidget);
    await tester.tap(find.text('Все'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alisher'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('просроченный должник попадает в фильтр и получает бейдж', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      final id = await repo.createDebtor(const DebtorInput(name: 'Bobur'));
      await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 300000,
        occurredAt: DateTime.now().subtract(const Duration(days: 45)),
      );
    });
    await openDebts(tester);

    expect(find.text('Просрочен'), findsOneWidget);
    await tester.tap(find.text('Просроченные'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bobur'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('удаление должника из карточки возвращает в пустую книгу', (tester) async {
    await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      final id = await repo.createDebtor(const DebtorInput(name: 'Davron'));
      await repo.addTransaction(
        debtorId: id,
        kind: DebtKind.debt,
        amount: 1000,
        occurredAt: DateTime.now(),
      );
    });
    await openDebts(tester);

    await tester.tap(find.text('Davron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Удалить должника?'), findsOneWidget);
    await tapAsync(tester, find.widgetWithText(FilledButton, 'Удалить'));
    await settle(tester);

    expect(find.text('Пока нет должников'), findsOneWidget);
    final all = await tester.runAsync(() => DebtorsRepository(db).loadSummaries());
    expect(all, isEmpty);

    await closeApp(tester);
  });
}
