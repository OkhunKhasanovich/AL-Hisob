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
import 'package:al_hisob/features/debts/presentation/debts_overview_card.dart';
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

  testWidgets('панель вкладок — во всю ширину, у самого низа, только значки', (tester) async {
    await openApp(tester);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bar = find.byType(FloatingNavBar);
    final whole = tester.getRect(bar);
    expect(whole.left, 0, reason: 'от левого края экрана');
    expect(whole.right, size.width, reason: 'до правого края экрана');
    expect(whole.bottom, size.height, reason: 'прижата к низу, пустой полосы под ней нет');
    final row = tester.getRect(find.descendant(of: bar, matching: find.byType(SizedBox)).first);
    expect(row.height, floatingNavHeight, reason: 'невысокая');
    expect(row.width, size.width);

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

    final material = tester.widget<Material>(
      find.descendant(of: bar, matching: find.byType(Material)).first,
    );
    expect(material.color!.a, 1, reason: 'сплошной цвет');

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

  testWidgets('под панелью нет подложки: страница заходит под неё', (tester) async {
    await openApp(tester);
    final shell = tester.widget<Scaffold>(
      find.ancestor(of: find.byType(FloatingNavBar), matching: find.byType(Scaffold)).first,
    );
    expect(shell.extendBody, isTrue);

    // Вокруг «таблетки» нет закрашенной полосы: у панели сплошной цвет только у самой таблетки.
    final bar = find.byType(FloatingNavBar);
    final fills = tester
        .widgetList<ColoredBox>(find.descendant(of: bar, matching: find.byType(ColoredBox)))
        .where((b) => b.color.a > 0);
    expect(fills, isEmpty, reason: 'ни скрима, ни фона под панелью');

    await closeApp(tester);
  });

  testWidgets('строка поиска закреплена на сплошном фоне цвета страницы', (tester) async {
    await openApp(tester);
    final header = tester.widget<ColoredBox>(find.byKey(const ValueKey('search-header')));
    final page = Theme.of(tester.element(find.byKey(const ValueKey('search-header'))))
        .scaffoldBackgroundColor;
    expect(header.color, page, reason: 'плашки не видно');
    expect(header.color.a, 1, reason: 'карточки под полем не просвечивают');
    expect(find.byType(BackdropFilter), findsNothing);

    await closeApp(tester);
  });

  testWidgets('шторка из вкладки закрывает панель вкладок, а не оказывается над ней', (tester) async {
    await openApp(tester);
    final pill = tester.getRect(find.byType(FloatingNavBar));

    await tester.tap(find.byTooltip('Фильтры'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final sheet = tester.getRect(find.byType(BottomSheet));
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(sheet.bottom, closeTo(size.height, 1), reason: 'шторка доходит до низа экрана');
    expect(sheet.top, lessThan(pill.top), reason: 'и закрывает собой панель вкладок');

    await closeApp(tester);
  });

  testWidgets('уведомление (SnackBar) не прячется за панелью вкладок', (tester) async {
    await openApp(tester);
    final pill = tester.getRect(find.byType(FloatingNavBar));

    ScaffoldMessenger.of(tester.element(find.byType(FloatingActionButton)))
        .showSnackBar(const SnackBar(content: Text('Готово')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final snack = tester.getRect(find.byType(SnackBar));
    expect(snack.bottom, lessThanOrEqualTo(pill.top), reason: 'выше панели вкладок');

    await closeApp(tester);
  });

  testWidgets('вид главной карточки «Долги» запоминается между запусками', (tester) async {
    await openApp(tester);
    final card = find.byKey(const ValueKey('overview-card'));
    final detailed = tester.getSize(card).height;

    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.getSize(card).height, lessThan(detailed - 50));
    final saved = await tester.runAsync(() => SettingsRepository(db).load());
    expect(saved!.debtsOverviewCompact, isTrue);
    await closeApp(tester);

    // Новый запуск с сохранённым значением: сразу тонкая.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(saved),
      ],
      child: const AlHisobApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
    expect(tester.widget<DebtsOverviewCard>(find.byType(DebtsOverviewCard)).initialCompact, isTrue);
    expect(tester.getSize(find.byKey(const ValueKey('overview-card'))).height, lessThan(detailed - 50));
    await closeApp(tester);
  });

  testWidgets('«Ещё»: компактные блоки; язык выбирается из меню, тема — значками', (tester) async {
    await openApp(tester);
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Тема — три значка с подсказками, без длинных подписей.
    for (final tip in ['Как в системе', 'Светлая', 'Тёмная']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(find.text('Как в системе'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing, reason: 'языки не раскрыты россыпью фишек');

    // Строки плотные: заметно ниже обычных (56).
    final rowHeight = tester.getSize(find.widgetWithText(ListTile, 'Язык')).height;
    expect(rowHeight, lessThanOrEqualTo(48));

    // Язык: открыть шторку и выбрать English — подписи меняются.
    await tester.tap(find.widgetWithText(ListTile, 'Язык'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Language'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('системные кнопки: значки стоят выше них, а фон панели идёт до самого низа', (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 144); // 48 dp при плотности 3
    tester.view.viewPadding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await openApp(tester);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bar = find.byType(FloatingNavBar);
    final whole = tester.getRect(bar);
    final row = tester.getRect(find.descendant(of: bar, matching: find.byType(SizedBox)).first);
    expect(whole.bottom, size.height, reason: 'фон до самого низа экрана');
    expect(row.bottom, closeTo(size.height - 48, 0.5), reason: 'значки над системными кнопками');
    expect(whole.height, closeTo(floatingNavHeight + 48, 0.5));
    await closeApp(tester);
  });

  testWidgets('нажатие на значок вкладки не рисует ripple и подсветку', (tester) async {
    await openApp(tester);
    final bar = find.byType(FloatingNavBar);
    expect(find.descendant(of: bar, matching: find.byType(InkResponse)), findsNothing);
    expect(find.descendant(of: bar, matching: find.byType(InkWell)), findsNothing);

    // Пока палец прижат, панель выглядит так же, как до нажатия: вспышки нет.
    final gesture = await tester.startGesture(
      tester.getCenter(find.descendant(of: bar, matching: find.byTooltip('Ещё'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final material = tester.renderObject(find.descendant(of: bar, matching: find.byType(Material)).first);
    expect(material, isNot(paints..circle()), reason: 'ripple не рисуется');
    await gesture.up();
    await tester.pump(); // кадр, с которого стартует анимация пятна
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getCenter(find.byKey(const ValueKey('nav-indicator'))).dx, greaterThan(250),
        reason: 'вкладка при этом переключается');
    await closeApp(tester);
  });
}
