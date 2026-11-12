import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/app.dart';
import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/core/settings/settings_repository.dart';
import 'package:al_hisob/features/debts/data/debtors_repository.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';
import 'package:al_hisob/features/shell/floating_nav_bar.dart';

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

  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await ShopProfileRepository(db).create(name: 'Shop', roles: {ShopRole.wholesaler});
      await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Alisher'));
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider
            .overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
      ],
      child: const AlHisobApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('панель вкладок — плавающая «таблетка» только со значками', (tester) async {
    await openApp(tester);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bar = find.byType(FloatingNavBar);
    final pill = tester.getRect(find.descendant(of: bar, matching: find.byType(SizedBox)).first);
    expect(pill.height, floatingNavHeight, reason: 'невысокая');
    expect(pill.left, greaterThan(10), reason: 'не прилипает к левому краю');
    expect(pill.right, lessThan(size.width - 10), reason: 'не прилипает к правому краю');
    expect(pill.bottom, lessThan(size.height - 4), reason: 'плавает над нижним краем');

    for (final label in ['Долги', 'Заказы', 'Каталог', 'Ещё']) {
      expect(find.descendant(of: bar, matching: find.byTooltip(label)), findsOneWidget);
    }
    expect(find.descendant(of: bar, matching: find.text('Каталог')), findsNothing,
        reason: 'подписей нет');

    await closeApp(tester);
  });

  testWidgets('без стекла: ни размытия, ни полупрозрачности', (tester) async {
    await openApp(tester);
    final bar = find.byType(FloatingNavBar);
    expect(find.descendant(of: bar, matching: find.byType(BackdropFilter)), findsNothing);

    final container = tester
        .widgetList<DecoratedBox>(find.descendant(of: bar, matching: find.byType(DecoratedBox)))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color != null && d.border != null);
    expect(container.color!.a, 1, reason: 'сплошной цвет');

    await closeApp(tester);
  });

  testWidgets('пятно под активной вкладкой переезжает при переключении', (tester) async {
    await openApp(tester);
    final indicator = find.byKey(const ValueKey('nav-indicator'));
    final before = tester.getCenter(indicator).dx;

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getCenter(indicator).dx, greaterThan(before + 100));
    await closeApp(tester);
  });

  testWidgets('кнопка «Добавить должника» не заходит на панель вкладок', (tester) async {
    await openApp(tester);
    final fab = tester.getRect(find.byType(FloatingActionButton));
    final pill = tester.getRect(find.byType(FloatingNavBar));
    expect(fab.bottom, lessThanOrEqualTo(pill.top));
    await closeApp(tester);
  });
}
