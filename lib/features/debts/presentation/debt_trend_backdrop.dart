import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../domain/debt_trend.dart';

/// Где на карточке рисуется линия: начинается с 40% ширины и идёт до правого края.
const trendStartFraction = 0.4;

/// Толщина линии: тонкая в начале, к концу утолщается.
const trendMinWidth = 0.8;
const trendMaxWidth = 5.0;

/// Цвет динамики: рост долга — тревожный, снижение — спокойный.
Color trendColor(ColorScheme scheme, DebtTrendDirection direction) => switch (direction) {
  DebtTrendDirection.up => scheme.error,
  DebtTrendDirection.down => const Color(0xFF2E9D57),
  DebtTrendDirection.flat => scheme.primary,
};

/// Место над концом линии под процент (рядом сверху подписан период).
const _roomAbove = 50.0;

/// Место под концом линии под процент.
const _roomBelow = 34.0;

/// Куда ставить процент: растущий долг приходит к точке снизу — процент над ней,
/// падающий приходит сверху — процент под ней, чтобы линия не пряталась за текстом.
bool trendLabelAbove(DebtTrendDirection direction) => direction != DebtTrendDirection.down;

/// Точки линии в координатах карточки размером [size]. Старые дни — слева.
/// Над или под концом линии остаётся место для процента ([labelAbove]).
List<Offset> trendOffsets(List<int> values, Size size, {bool labelAbove = true}) {
  if (values.length < 2) return const [];
  final left = size.width * trendStartFraction;
  final right = size.width - 22; // справа остаётся место под мигающую точку
  var top = size.height * 0.30;
  var bottom = size.height * 0.88;
  if (labelAbove) {
    top = math.max(top, _roomAbove);
  } else {
    bottom = math.min(bottom, size.height - _roomBelow);
  }
  if (bottom - top < 24) {
    // Карточка слишком низкая — лучше сжать линию, чем выйти за края.
    top = size.height * 0.30;
    bottom = size.height * 0.88;
  }
  final lo = values.reduce(math.min);
  final hi = values.reduce(math.max);
  final range = (hi - lo).toDouble();
  return [
    for (var i = 0; i < values.length; i++)
      Offset(
        left + (right - left) * i / (values.length - 1),
        // Без перепадов — ровная линия посередине.
        range == 0 ? (top + bottom) / 2 : bottom - (bottom - top) * (values[i] - lo) / range,
      ),
  ];
}

/// Фон карточки: линия динамики общего долга, мигающая точка на конце,
/// процент у точки и полупрозрачная подпись периода сверху (по центру правой половины).
class DebtTrendBackdrop extends StatefulWidget {
  const DebtTrendBackdrop({super.key, required this.trend});

  final DebtTrend trend;

  @override
  State<DebtTrendBackdrop> createState() => _DebtTrendBackdropState();
}

class _DebtTrendBackdropState extends State<DebtTrendBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _animate = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // При включённом «убрать анимации» точка просто горит.
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate == _animate && _blink.isAnimating == animate) return;
    _animate = animate;
    if (animate) {
      _blink.repeat(reverse: true);
    } else {
      _blink
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final trend = widget.trend;
    final color = trendColor(scheme, trend.direction);
    final percent = formatTrendPercent(trend) ?? l10n.debtsTrendNew;
    final period = l10n.debtsTrendPeriod(trend.days);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final labelAbove = trendLabelAbove(trend.direction);
        final offsets = trendOffsets(trend.points, size, labelAbove: labelAbove);
        if (offsets.isEmpty) return const SizedBox.shrink();
        final end = offsets.last;

        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(Object.hashAll(trend.points)),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) => CustomPaint(
                  painter: _TrendPainter(
                    offsets: offsets,
                    color: color,
                    progress: progress,
                    blink: _blink,
                    startX: size.width * trendStartFraction,
                  ),
                ),
              ),
            ),
            // Период — вверху, по центру правой половины (на 3/4 ширины), едва заметный.
            Positioned(
              top: 17,
              left: size.width * 0.5,
              right: 0,
              child: ExcludeSemantics(
                child: Center(
                  child: Text(
                    period,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            // Процент — просто цифра у конца линии, без плашки.
            Positioned(
              right: 12,
              top: labelAbove ? null : end.dy + 9,
              bottom: labelAbove ? size.height - end.dy + 9 : null,
              child: Semantics(
                label: '$percent, $period',
                child: ExcludeSemantics(
                  child: _PercentLabel(text: percent, color: color, direction: trend.direction),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PercentLabel extends StatelessWidget {
  const _PercentLabel({required this.text, required this.color, required this.direction});

  final String text;
  final Color color;
  final DebtTrendDirection direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Чуть темнее цвета линии, чтобы читалось на светлом фоне.
    final textColor = Color.lerp(color, theme.colorScheme.onSurface, 0.2)!;
    final arrow = switch (direction) {
      DebtTrendDirection.up => Icons.arrow_drop_up_rounded,
      DebtTrendDirection.down => Icons.arrow_drop_down_rounded,
      DebtTrendDirection.flat => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (arrow != null) Icon(arrow, size: 22, color: textColor),
        Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

/// Отсчёт вдоль линии: точка, единичная нормаль и толщина в этой точке.
class _Sample {
  const _Sample(this.p, this.n, this.width);
  final Offset p;
  final Offset n;
  final double width;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.offsets,
    required this.color,
    required this.progress,
    required this.blink,
    required this.startX,
  }) : super(repaint: blink);

  final List<Offset> offsets;
  final Color color;

  /// 0…1 — линия «дорисовывается» слева направо при появлении.
  final double progress;
  final Animation<double> blink;
  final double startX;

  /// Плавная ступенька: горизонтальные касательные не дают «перелёта» за min/max.
  Path _centerLine() {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      final a = offsets[i - 1], b = offsets[i];
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    return path;
  }

  /// Отсчёты вдоль видимой части линии; толщина растёт от начала к концу.
  /// Считается один раз на экземпляр: мигание перерисовывает тот же painter.
  late final List<_Sample> _samples = () {
    final metrics = _centerLine().computeMetrics().toList();
    if (metrics.isEmpty) return const <_Sample>[];
    final metric = metrics.first;
    final total = metric.length;
    final visible = total * progress.clamp(0.0, 1.0);
    final result = <_Sample>[];
    const step = 2.0;
    for (var d = 0.0;; d += step) {
      final at = math.min(d, visible);
      final tangent = metric.getTangentForOffset(at);
      if (tangent == null) break;
      final v = tangent.vector;
      result.add(_Sample(
        tangent.position,
        Offset(-v.dy, v.dx),
        trendMinWidth + (trendMaxWidth - trendMinWidth) * (total == 0 ? 1 : at / total),
      ));
      if (at >= visible) break;
    }
    return result;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final samples = _samples;
    if (samples.length < 2) return;
    final endX = offsets.last.dx;
    final tip = samples.last.p;
    final bounds = Rect.fromLTRB(startX, 0, endX + 24, size.height);

    // Заливка под линией: сверху вниз гаснет, а слева растворяется (маска dstIn).
    canvas.saveLayer(bounds, Paint());
    final area = Path()..moveTo(samples.first.p.dx, samples.first.p.dy);
    for (final s in samples.skip(1)) {
      area.lineTo(s.p.dx, s.p.dy);
    }
    area
      ..lineTo(tip.dx, size.height)
      ..lineTo(samples.first.p.dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          colors: [Color(0x00000000), Color(0xFF000000)],
          stops: [0, 0.35],
        ).createShader(Rect.fromLTRB(startX, 0, endX, size.height)),
    );
    canvas.restore();

    // Линия переменной толщины: контур из левых и правых краёв вдоль нормали.
    final outline = Path()
      ..moveTo(
        samples.first.p.dx + samples.first.n.dx * samples.first.width / 2,
        samples.first.p.dy + samples.first.n.dy * samples.first.width / 2,
      );
    for (final s in samples.skip(1)) {
      outline.lineTo(s.p.dx + s.n.dx * s.width / 2, s.p.dy + s.n.dy * s.width / 2);
    }
    for (final s in samples.reversed) {
      outline.lineTo(s.p.dx - s.n.dx * s.width / 2, s.p.dy - s.n.dy * s.width / 2);
    }
    outline.close();
    final fade = LinearGradient(
      colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.92)],
      stops: const [0, 0.35],
    ).createShader(Rect.fromLTRB(startX, 0, endX, size.height));
    canvas.drawPath(outline, Paint()..shader = fade);
    // Круглый конец той же толщины, что и у линии.
    canvas.drawCircle(tip, trendMaxWidth / 2, Paint()..color = color.withValues(alpha: 0.92));

    if (progress < 1) return;
    // Медленно мигающая точка на конце линии.
    final t = Curves.easeInOut.transform(blink.value);
    canvas.drawCircle(tip, 6 + 8 * t, Paint()..color = color.withValues(alpha: 0.28 * (1 - t) + 0.06));
    canvas.drawCircle(tip, 4.5, Paint()..color = color.withValues(alpha: 0.55 + 0.45 * (1 - t)));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.offsets != offsets || old.color != color || old.progress != progress || old.startX != startX;
}
