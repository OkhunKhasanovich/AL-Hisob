import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../domain/debt_trend.dart';

/// Где на карточке рисуется линия: начинается с 40% ширины и идёт до правого края.
const trendStartFraction = 0.4;

/// Толщина линии: тонкая в начале, к концу утолщается.
const trendMinWidth = 0.7;
const trendMaxWidth = 2.8;

/// Цвет динамики: рост долга — тревожный, снижение — спокойный.
Color trendColor(ColorScheme scheme, DebtTrendDirection direction) => switch (direction) {
  DebtTrendDirection.up => scheme.error,
  DebtTrendDirection.down => const Color(0xFF2E9D57),
  DebtTrendDirection.flat => scheme.primary,
};

/// Свободное место сверху полосы графика: там стоит процент.
const _topReserve = 26.0;

/// Отступ снизу полосы, чтобы линия и мигающая точка не прилипали к краю.
const _bottomReserve = 8.0;

/// Точки линии в координатах полосы графика размером [band]. Старые дни — слева.
/// Линия лежит ниже строки с процентом, поэтому с ним не пересекается.
List<Offset> trendOffsets(List<int> values, Size band) {
  if (values.length < 2) return const [];
  final left = band.width * trendStartFraction;
  final right = band.width - 22; // справа остаётся место под мигающую точку
  var top = _topReserve;
  var bottom = band.height - _bottomReserve;
  if (bottom - top < 16) {
    // Полоса слишком низкая — лучше сжать запас, чем выйти за края.
    top = band.height * 0.3;
    bottom = band.height * 0.9;
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

/// Слой карточки: линия динамики общего долга в своей полосе (с 40% ширины до правого края),
/// мигающая точка на конце, процент над линией и полупрозрачная подпись периода
/// вверху на 3/4 ширины. Полоса — [bandHeight] над нижним отступом [bottomInset].
class DebtTrendBackdrop extends StatefulWidget {
  const DebtTrendBackdrop({
    super.key,
    required this.trend,
    this.bandHeight = 68,
    this.bottomInset = 16,
  });

  final DebtTrend trend;
  final double bandHeight;
  final double bottomInset;

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
        final bandTop = size.height - widget.bottomInset - widget.bandHeight;
        final band = Size(size.width, widget.bandHeight);
        final local = trendOffsets(trend.points, band);
        if (local.isEmpty) return const SizedBox.shrink();
        final offsets = [for (final o in local) o.translate(0, bandTop)];

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
                    bandTop: bandTop,
                    bandBottom: bandTop + widget.bandHeight,
                  ),
                ),
              ),
            ),
            // Период — вверху, по центру правой половины (на 3/4 ширины), едва заметный.
            Positioned(
              top: 16,
              height: 20,
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
            // Процент — над линией у правого края, без плашки.
            Positioned(
              right: 14,
              top: bandTop,
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
        if (arrow != null) Icon(arrow, size: 18, color: textColor),
        Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w700,
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
    required this.bandTop,
    required this.bandBottom,
  }) : super(repaint: blink);

  final List<Offset> offsets;
  final Color color;

  /// 0…1 — линия «дорисовывается» слева направо при появлении.
  final double progress;
  final Animation<double> blink;
  final double startX;
  final double bandTop;
  final double bandBottom;

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
    final bounds = Rect.fromLTRB(startX, bandTop, endX + 24, bandBottom);

    // Заливка под линией: сверху вниз гаснет, а слева растворяется (маска dstIn).
    canvas.saveLayer(bounds, Paint());
    final area = Path()..moveTo(samples.first.p.dx, samples.first.p.dy);
    for (final s in samples.skip(1)) {
      area.lineTo(s.p.dx, s.p.dy);
    }
    area
      ..lineTo(tip.dx, bandBottom)
      ..lineTo(samples.first.p.dx, bandBottom)
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
        ).createShader(Rect.fromLTRB(startX, bandTop, endX, bandBottom)),
    );
    canvas.restore();

    // Тонкая направляющая у основания полосы и метки дней — график выглядит «приборным».
    final guide = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var x = startX; x < endX + 12; x += 6) {
      canvas.drawLine(Offset(x, bandBottom), Offset(math.min(x + 2, endX + 12), bandBottom), guide);
    }
    final span = math.max(1.0, (endX - startX) * 0.35);
    for (final o in offsets.take(offsets.length - 1)) {
      if (o.dx > tip.dx) break; // ещё не дорисована
      final a = ((o.dx - startX) / span).clamp(0.0, 1.0);
      canvas.drawCircle(o, 1.8, Paint()..color = color.withValues(alpha: 0.5 * a));
    }

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
    ).createShader(Rect.fromLTRB(startX, bandTop, endX, bandBottom));
    canvas.drawPath(outline, Paint()..shader = fade);
    // Круглый конец той же толщины, что и у линии.
    canvas.drawCircle(tip, trendMaxWidth / 2, Paint()..color = color.withValues(alpha: 0.92));

    if (progress < 1) return;
    // Медленно мигающая точка на конце линии.
    final t = Curves.easeInOut.transform(blink.value);
    canvas.drawCircle(tip, 4.5 + 6 * t, Paint()..color = color.withValues(alpha: 0.28 * (1 - t) + 0.06));
    canvas.drawCircle(tip, 3.5, Paint()..color = color.withValues(alpha: 0.55 + 0.45 * (1 - t)));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.offsets != offsets || old.color != color || old.progress != progress || old.startX != startX;
}
