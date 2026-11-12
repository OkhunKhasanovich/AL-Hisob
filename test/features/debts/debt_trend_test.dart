import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/database/sync_columns.dart';
import 'package:al_hisob/core/domain/debt_kind.dart';
import 'package:al_hisob/core/l10n/l10n.dart';
import 'package:al_hisob/features/debts/domain/debt_filter.dart';
import 'package:al_hisob/features/debts/domain/debt_trend.dart';
import 'package:al_hisob/features/debts/presentation/debt_trend_backdrop.dart';
import 'package:al_hisob/features/debts/presentation/debts_overview_card.dart';

DebtTransaction _tx(String debtor, DebtKind kind, int amount, DateTime at, {DateTime? deletedAt}) =>
    DebtTransaction(
      id: '$debtor-${kind.index}-$amount-${at.millisecondsSinceEpoch}',
      createdAt: at,
      updatedAt: at,
      deletedAt: deletedAt,
      syncStatus: SyncStatus.pending,
      debtorId: debtor,
      kind: kind,
      amount: amount,
      occurredAt: at,
    );

void main() {
  final now = DateTime(2026, 6, 30, 12);
  DateTime daysAgo(int d, [int hour = 10]) => DateTime(2026, 6, 30 - d, hour);

  group('computeDebtTrend', () {
    test('по умолчанию — неделя: 7 точек', () {
      final trend = computeDebtTrend([
        _tx('a', DebtKind.debt, 1000, daysAgo(20)),
        _tx('a', DebtKind.debt, 300, daysAgo(2)),
      ], now: now);
      expect(defaultTrendDays, 7);
      expect(trend.points, [1000, 1000, 1000, 1000, 1300, 1300, 1300]);
      expect(trend.percent, closeTo(30, 1e-9));
    });

    test('30 точек, последняя равна общему долгу', () {
      final trend = computeDebtTrend([
        _tx('a', DebtKind.debt, 1000, daysAgo(40)),
        _tx('a', DebtKind.payment, 400, daysAgo(10)),
        _tx('b', DebtKind.debt, 500, daysAgo(2)),
      ], now: now, days: 30);
      expect(trend.points.length, 30);
      expect(trend.first, 1000, reason: 'долг a на начало периода');
      expect(trend.points[18], 1000, reason: 'за день до оплаты');
      expect(trend.points[19], 600, reason: 'день оплаты: 10 дней назад');
      expect(trend.last, 1100);
      expect(trend.change, 100);
    });

    test('переплата не вычитается из общего долга', () {
      final txs = [
        _tx('a', DebtKind.debt, 1000, daysAgo(5)),
        _tx('b', DebtKind.debt, 300, daysAgo(3)),
        _tx('b', DebtKind.payment, 800, daysAgo(1)), // переплата 500
      ];
      expect(computeDebtTrend(txs, now: now).last, 1000, reason: 'как totalOwed: 1000 + 0, без −500');
    });

    test('оплата в тот же день, что и выдача, учитывается в этом дне', () {
      final trend = computeDebtTrend([
        _tx('a', DebtKind.debt, 1000, daysAgo(0, 8)),
        _tx('a', DebtKind.payment, 1000, daysAgo(0, 9)),
      ], now: now);
      expect(trend.last, 0);
      expect(trend.isEmpty, isTrue);
    });

    test('удалённые операции игнорируются', () {
      final trend = computeDebtTrend([
        _tx('a', DebtKind.debt, 1000, daysAgo(5)),
        _tx('a', DebtKind.debt, 9999, daysAgo(4), deletedAt: now),
      ], now: now);
      expect(trend.last, 1000);
    });

    test('операции из будущего попадают в последнюю точку', () {
      final trend = computeDebtTrend([
        _tx('a', DebtKind.debt, 700, now.add(const Duration(days: 3))),
      ], now: now, days: 30);
      expect(trend.last, 700);
      expect(trend.points[28], 0);
    });

    test('работает через границу месяца и года', () {
      final trend = computeDebtTrend(
        [_tx('a', DebtKind.debt, 100, DateTime(2026, 1, 1, 9))],
        now: DateTime(2026, 1, 10, 12),
        days: 15,
      );
      expect(trend.points.length, 15);
      expect(trend.points[0], 0, reason: '17 декабря');
      expect(trend.points[14 - 9], 100, reason: '1 января');
      expect(trend.points[14 - 10], 0, reason: '31 декабря');
    });

    test('без операций — пусто', () {
      expect(computeDebtTrend(const [], now: now).isEmpty, isTrue);
    });
  });

  group('процент и направление', () {
    DebtTrend t(List<int> p) => DebtTrend(points: p);

    test('рост, снижение, без изменений', () {
      expect(t([100, 150]).direction, DebtTrendDirection.up);
      expect(t([100, 40]).direction, DebtTrendDirection.down);
      expect(t([100, 100]).direction, DebtTrendDirection.flat);
    });

    test('процент считается от долга на начало периода', () {
      expect(t([1000, 1120]).percent, closeTo(12, 1e-9));
      expect(t([1000, 600]).percent, closeTo(-40, 1e-9));
      expect(t([0, 500]).percent, isNull, reason: 'в начале долга не было');
    });

    test('формат индекса', () {
      expect(formatTrendPercent(t([1000, 1120])), '+12%');
      expect(formatTrendPercent(t([1000, 600])), '−40%');
      expect(formatTrendPercent(t([1000, 946])), '−5.4%');
      expect(formatTrendPercent(t([1000, 1050])), '+5%');
      expect(formatTrendPercent(t([1000, 1000])), '0%');
      expect(formatTrendPercent(t([100000, 100001])), '+0.1%', reason: 'малое, но не ноль');
      expect(formatTrendPercent(t([10, 1000])), '+>999%');
      expect(formatTrendPercent(t([0, 500])), isNull);
    });
  });

  group('геометрия линии', () {
    test('начинается с 40% ширины и кончается у правого края, рост — вверх', () {
      const size = Size(400, 68);
      final o = trendOffsets([0, 50, 100], size);
      expect(o.first.dx, closeTo(160, 1e-9));
      expect(o.last.dx, lessThanOrEqualTo(400));
      expect(o.last.dx, greaterThan(350));
      expect(o.last.dy, lessThan(o.first.dy), reason: 'больше долг — выше');
    });

    test('ровная линия — по центру', () {
      final o = trendOffsets([5, 5, 5], const Size(400, 68));
      expect(o.map((e) => e.dy).toSet().length, 1);
    });
  });

  group('карточка', () {
    Future<void> pump(WidgetTester tester, DebtTrend? trend, {bool animations = true}) {
      return tester.pumpWidget(MediaQuery(
        data: MediaQueryData(disableAnimations: !animations),
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(
            body: DebtsOverviewCard(
              overview: const DebtsOverview(
                totalOwed: 1120,
                debtorCount: 2,
                overdueCount: 0,
                overdueAmount: 0,
              ),
              trend: trend,
            ),
          ),
        ),
      ));
    }

    testWidgets('показывает индекс и период; линия мигает без остановки кадров', (tester) async {
      await pump(tester, DebtTrend(points: [for (var i = 0; i < 30; i++) 1000 + i * 4]));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('+12%'), findsOneWidget);
      expect(find.text('за 30 дн.'), findsOneWidget, reason: 'период — отдельным текстом');
      expect(find.byIcon(Icons.arrow_drop_up_rounded), findsOneWidget);
      expect(find.text('Вам должны'), findsOneWidget);

      // Точка мигает: анимация продолжает просить кадры.
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('период — крупный полупрозрачный фон за линией, правее 40% ширины', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester, DebtTrend(points: [for (var i = 0; i < 7; i++) 1000 + i * 20]));
      await tester.pump(const Duration(milliseconds: 1000));

      final card = tester.getRect(find.byType(DebtsOverviewCard));
      final periodFinder = find.byKey(const ValueKey('trend-period'));
      final period = tester.getRect(periodFinder);
      final style = tester.widget<Text>(periodFinder).style!;
      expect(style.color!.a, lessThan(0.25), reason: 'полупрозрачный');
      expect(style.fontSize!, greaterThan(30), reason: 'крупный');
      expect(period.left, greaterThanOrEqualTo(card.left + card.width * 0.4 - 1));
      expect(period.top, greaterThan(card.top + card.height * 0.4), reason: 'в полосе графика, не в шапке');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('двойное нажатие: плавно переключает подробный и тонкий вид', (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: DebtsOverviewCard(
            overview: const DebtsOverview(totalOwed: 1120, debtorCount: 2, overdueCount: 1, overdueAmount: 5),
            trend: DebtTrend(points: [for (var i = 0; i < 7; i++) 1000 + i * 20]),
            onCompactChanged: changes.add,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1000));
      final card = find.byKey(const ValueKey('overview-card'));
      final detailedHeight = tester.getSize(card).height;
      expect(find.byKey(const ValueKey('trend-period')), findsOneWidget, reason: 'подробный вид с графиком');

      Future<void> doubleTap() async {
        await tester.tap(card);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(card);
      }

      // Одно нажатие вид не меняет.
      await tester.tap(card);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(card).height, detailedHeight);

      // Двойное: в середине перехода высота между двумя значениями, затем тонкий вид.
      await doubleTap();
      await tester.pump(); // кадр, с которого стартует анимация
      await tester.pump(const Duration(milliseconds: 120));
      final mid = tester.getSize(card).height;
      await tester.pump(const Duration(milliseconds: 800));
      final compactHeight = tester.getSize(card).height;
      expect(changes, [true]);
      expect(compactHeight, lessThan(detailedHeight - 50), reason: 'тонкий вид заметно ниже');
      expect(compactHeight, lessThan(90), reason: 'тонкий');
      expect(mid, lessThan(detailedHeight));
      expect(mid, greaterThan(compactHeight), reason: 'высота меняется плавно, а не прыжком');
      expect(find.byKey(const ValueKey('trend-period')), findsNothing, reason: 'без динамики');
      expect(find.text('Вам должны'), findsOneWidget);
      expect(find.textContaining('1 120'), findsOneWidget, reason: 'сумма на месте');
      expect(find.byKey(const ValueKey('stat-debtors')), findsOneWidget);
      expect(find.byKey(const ValueKey('stat-overdue')), findsOneWidget);

      // Обратно.
      await doubleTap();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(changes, [true, false]);
      expect(tester.getSize(card).height, closeTo(detailedHeight, 1));
      expect(find.byKey(const ValueKey('trend-period')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('переход — непрерывное перетекание: ничего не накладывается и не прыгает', (tester) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: DebtsOverviewCard(
            overview: const DebtsOverview(totalOwed: 234221000, debtorCount: 51, overdueCount: 17, overdueAmount: 1),
            trend: DebtTrend(points: [for (var i = 0; i < 7; i++) 200 + i * 5]),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1200));
      final card = find.byKey(const ValueKey('overview-card'));

      final heights = <double>[];
      final statsLeft = <double>[];
      final statsTop = <double>[];
      final amountLeft = <double>[];

      void sample() {
        heights.add(tester.getSize(card).height);
        final debtors = tester.getRect(find.byKey(const ValueKey('stat-debtors')));
        final overdue = tester.getRect(find.byKey(const ValueKey('stat-overdue')));
        final stats = debtors.expandToInclude(overdue);
        final amount = tester.getRect(find.textContaining('сум'));
        final label = tester.getRect(find.text('Вам должны'));
        statsLeft.add(stats.left);
        statsTop.add(stats.top);
        amountLeft.add(amount.left);
        // Видимые прямоугольники (без запаса на касание) не пересекаются в любой момент.
        final tapPad = 6.0;
        final visibleStats = Rect.fromLTRB(stats.left, stats.top + tapPad, stats.right, stats.bottom - tapPad);
        expect(visibleStats.overlaps(amount.deflate(1)), isFalse, reason: 'сводка и сумма: $visibleStats vs $amount');
        expect(label.overlaps(amount.deflate(1)), isFalse, reason: 'подпись и сумма');
        expect(visibleStats.overlaps(label.deflate(1)), isFalse, reason: 'сводка и подпись');
        // Всё внутри карточки.
        final box = tester.getRect(card);
        expect(box.inflate(1).contains(visibleStats.topLeft) && box.inflate(1).contains(visibleStats.bottomRight), isTrue,
            reason: 'сводка внутри карточки');
      }

      Future<void> run() async {
        await tester.tap(card);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(card);
        await tester.pump();
        for (var i = 0; i < 16; i++) {
          sample();
          await tester.pump(const Duration(milliseconds: 32));
        }
        await tester.pump(const Duration(milliseconds: 400));
        sample();
      }

      await run(); // подробный → тонкий
      for (var i = 1; i < heights.length; i++) {
        expect(heights[i], lessThanOrEqualTo(heights[i - 1] + 0.01), reason: 'высота убывает без скачков вверх');
        expect(statsLeft[i], greaterThanOrEqualTo(statsLeft[i - 1] - 0.01), reason: 'сводка едет только вправо');
        expect(statsTop[i] - statsTop[i - 1], lessThan(40), reason: 'нет скачков по вертикали');
        expect(amountLeft[i], closeTo(amountLeft[0], 0.5), reason: 'сумма остаётся у левого края');
      }
      expect(heights.last, lessThan(90));

      heights.clear(); statsLeft.clear(); statsTop.clear(); amountLeft.clear();
      await run(); // тонкий → подробный
      for (var i = 1; i < heights.length; i++) {
        expect(heights[i], greaterThanOrEqualTo(heights[i - 1] - 0.01), reason: 'высота растёт без скачков вниз');
        expect(statsLeft[i], lessThanOrEqualTo(statsLeft[i - 1] + 0.01), reason: 'сводка едет только влево');
      }
      expect(heights.last, greaterThan(150));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('повторное двойное нажатие посреди перехода плавно разворачивает карточку', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: DebtsOverviewCard(
            overview: const DebtsOverview(totalOwed: 1000, debtorCount: 3, overdueCount: 1, overdueAmount: 1),
            trend: DebtTrend(points: [for (var i = 0; i < 7; i++) 1000 + i * 20]),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1000));
      final card = find.byKey(const ValueKey('overview-card'));
      final full = tester.getSize(card).height;

      Future<void> doubleTap() async {
        await tester.tap(card);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(card);
        await tester.pump();
      }

      await doubleTap();
      await tester.pump(const Duration(milliseconds: 150));
      final mid = tester.getSize(card).height;
      expect(mid, lessThan(full));
      await doubleTap(); // передумали, пока карточка ещё сжимается
      await tester.pump(const Duration(milliseconds: 40));
      final soon = tester.getSize(card).height;
      expect(soon, greaterThan(mid - 1), reason: 'повернула обратно, а не доехала до тонкого вида');
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.getSize(card).height, closeTo(full, 1));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('счётчик просрочки нажимается; выбран — подсвечен', (tester) async {
      var taps = 0;
      Future<void> pump({required bool selected}) => tester.pumpWidget(MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ru'),
            home: Scaffold(
              body: DebtsOverviewCard(
                overview: const DebtsOverview(totalOwed: 1000, debtorCount: 3, overdueCount: 2, overdueAmount: 1),
                overdueSelected: selected,
                onOverdueTap: () => taps++,
              ),
            ),
          ));
      await pump(selected: false);
      await tester.tap(find.byKey(const ValueKey('stat-overdue')));
      await tester.pump(const Duration(milliseconds: 350)); // двойное нажатие карточки не засчитано
      expect(taps, 1);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('stat-overdue'))),
        isSemantics(isButton: true, isSelected: false),
      );
      await pump(selected: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getSemantics(find.byKey(const ValueKey('stat-overdue'))),
        isSemantics(isButton: true, isSelected: true),
      );
      // Счётчик должников не нажимается.
      await tester.tap(find.byKey(const ValueKey('stat-debtors')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('сохранённый тонкий вид: карточка сразу тонкая', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: DebtsOverviewCard(
            overview: const DebtsOverview(totalOwed: 500, debtorCount: 1, overdueCount: 0, overdueAmount: 0),
            trend: DebtTrend(points: [for (var i = 0; i < 7; i++) 1000 + i * 20]),
            initialCompact: true,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getSize(find.byKey(const ValueKey('overview-card'))).height, lessThan(90));
      expect(find.byKey(const ValueKey('trend-period')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('элементы карточки не накладываются друг на друга', (tester) async {
      tester.view.physicalSize = const Size(1233, 1600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // Реальные шрифты уже тестового, поэтому масштабируем текст.
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.55)),
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: const Scaffold(
            body: DebtsOverviewCard(
              overview: DebtsOverview(
                totalOwed: 234221000,
                debtorCount: 51,
                overdueCount: 17,
                overdueAmount: 0,
              ),
              trend: DebtTrend(points: [200, 200, 206, 205, 215, 222, 234]),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1500));

      final card = tester.getRect(find.byType(DebtsOverviewCard));
      final amount = tester.getRect(find.textContaining('сум'));
      final percent = tester.getRect(find.text('+17%'));
      final debtors = tester.getRect(find.byKey(const ValueKey('stat-debtors')));
      final overdue = tester.getRect(find.byKey(const ValueKey('stat-overdue')));

      expect(percent.overlaps(amount), isFalse, reason: 'процент и сумма');
      expect(debtors.overlaps(overdue), isFalse);
      expect(debtors.center.dy, closeTo(overdue.center.dy, 1), reason: 'значки в одной строке');
      expect(overdue.left, greaterThan(debtors.right));
      // Сводка слева не заходит на линию (она начинается с 40% ширины).
      final limit = card.left + card.width * 0.4;
      expect(overdue.right, lessThanOrEqualTo(limit));
      // Всё внутри карточки.
      for (final r in [amount, percent, debtors, overdue]) {
        expect(card.contains(r.topLeft) && card.contains(r.bottomRight), isTrue);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('сумма с середины карточки плавно бледнеет к правому краю', (tester) async {
      tester.view.physicalSize = const Size(1233, 1600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester, null);
      await tester.pump(const Duration(milliseconds: 700));

      final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(mask.blendMode, BlendMode.dstIn);
      // Слева прозрачности нет, а у правого края — есть.
      final box = tester.getRect(find.byType(ShaderMask));
      final shader = mask.shaderCallback(Rect.fromLTWH(0, 0, box.width, box.height));
      expect(shader, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('валюта в конце суммы полупрозрачная, число — нет', (tester) async {
      await pump(tester, null);
      final text = tester.widget<Text>(find.textContaining('сум'));
      final suffix = (text.textSpan! as TextSpan).children!.single as TextSpan;
      expect(suffix.text, ' сум');
      expect(suffix.style!.color!.a, lessThan(text.style!.color!.a), reason: 'валюта бледнее числа');
    });

    testWidgets('снижение долга — стрелка вниз и минус', (tester) async {
      await pump(tester, const DebtTrend(points: [1000, 900, 800]));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('−20%'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('в начале периода долга не было — «новые»', (tester) async {
      await pump(tester, const DebtTrend(points: [0, 0, 500]));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('новые'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('без анимаций кадры не запрашиваются', (tester) async {
      await pump(tester, const DebtTrend(points: [1000, 1100]), animations: false);
      await tester.pumpAndSettle();
      expect(find.text('+10%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('без данных графика нет', (tester) async {
      await pump(tester, null);
      expect(find.byType(DebtTrendBackdrop), findsNothing);
      expect(find.text('Вам должны'), findsOneWidget);
    });
  });
}
