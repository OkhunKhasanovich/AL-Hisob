import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/app.dart';
import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';
import 'package:al_savdogar/core/widgets/glass.dart';
import 'package:al_savdogar/features/debts/data/debtors_repository.dart';
import 'package:al_savdogar/features/profile/shop_profile_repository.dart';
import 'package:al_savdogar/core/domain/shop_role.dart';
import 'package:al_savdogar/features/shell/glass_nav_bar.dart';

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
      final repo = DebtorsRepository(db);
      for (final n in ['Alisher', 'Bobur', 'Davron']) {
        await repo.createDebtor(DebtorInput(name: n));
      }
    });
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

  testWidgets('нижняя панель — плавающая стеклянная «таблетка» только со значками', (tester) async {
    await openApp(tester);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final panel = tester.getRect(find.byType(GlassPanel));
    expect(panel.height, glassNavHeight, reason: 'невысокая');
    expect(panel.left, greaterThan(10), reason: 'не прилипает к левому краю');
    expect(panel.right, lessThan(size.width - 10), reason: 'не прилипает к правому краю');
    expect(panel.bottom, lessThan(size.height - 4), reason: 'плавает над нижним краем');

    for (final label in ['Долги', 'Заказы', 'Каталог', 'Ещё']) {
      expect(find.descendant(of: find.byType(GlassNavBar), matching: find.byTooltip(label)),
          findsOneWidget);
    }
    expect(find.descendant(of: find.byType(GlassNavBar), matching: find.text('Каталог')), findsNothing,
        reason: 'подписей нет');

    await closeApp(tester);
  });

  testWidgets('пятно под активной вкладкой переезжает при переключении', (tester) async {
    await openApp(tester);
    final indicator = find.byKey(const ValueKey('nav-indicator'));
    final before = tester.getCenter(indicator).dx;

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final after = tester.getCenter(indicator).dx;

    expect(after, greaterThan(before + 100));
    await closeApp(tester);
  });

  testWidgets('кнопка «Добавить должника» не прячется за панелью вкладок', (tester) async {
    await openApp(tester);
    final fab = tester.getRect(find.byType(FloatingActionButton));
    final panel = tester.getRect(find.byType(GlassPanel));
    expect(fab.bottom, lessThanOrEqualTo(panel.top), reason: 'кнопка выше панели');
    await closeApp(tester);
  });

  testWidgets('карточки должников — стекло с оттенком по состоянию', (tester) async {
    await openApp(tester);
    expect(find.byType(GlassCard), findsWidgets);
    await closeApp(tester);
  });
}
