import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/database/sync_columns.dart';
import 'package:al_savdogar/core/domain/debt_kind.dart';
import 'package:al_savdogar/core/l10n/l10n.dart';
import 'package:al_savdogar/features/debts/domain/debt_filter.dart';
import 'package:al_savdogar/features/debts/domain/debt_trend.dart';
import 'package:al_savdogar/features/debts/presentation/debt_trend_backdrop.dart';
import 'package:al_savdogar/features/debts/presentation/debts_overview_card.dart';

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
      const size = Size(400, 140);
      final o = trendOffsets([0, 50, 100], size);
      expect(o.first.dx, closeTo(160, 1e-9));
      expect(o.last.dx, lessThanOrEqualTo(400));
      expect(o.last.dx, greaterThan(350));
      expect(o.last.dy, lessThan(o.first.dy), reason: 'больше долг — выше');
    });

    test('ровная линия — по центру', () {
      final o = trendOffsets([5, 5, 5], const Size(400, 100));
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

    testWidgets('период — отдельно от процента, вверху на 3/4 ширины карточки', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester, DebtTrend(points: [for (var i = 0; i < 7; i++) 1000 + i * 20]));
      await tester.pump(const Duration(milliseconds: 1000));

      final card = tester.getRect(find.byType(DebtsOverviewCard));
      final period = tester.getCenter(find.text('за 7 дн.'));
      final percent = tester.getCenter(find.text('+12%'));
      expect(period.dx, closeTo(card.left + card.width * 0.75, card.width * 0.06),
          reason: 'подпись периода — на 3/4 ширины');
      expect(period.dy - card.top, lessThan(40), reason: 'вверху карточки');
      expect(percent.dy, greaterThan(period.dy), reason: 'процент у конца линии, а не в шапке');
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
