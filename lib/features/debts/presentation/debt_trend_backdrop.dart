import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../domain/debt_trend.dart';

/// Где на карточке рисуется линия: начинается с 40% ширины и идёт до правого края.
const trendStartFraction = 0.4;

/// Цвет динамики: рост долга — тревожный, снижение — спокойный.
Color trendColor(ColorScheme scheme, DebtTrendDirection direction) => switch (direction) {
  DebtTrendDirection.up => scheme.error,
  DebtTrendDirection.down => const Color(0xFF2E9D57),
  DebtTrendDirection.flat => scheme.primary,
};

/// Высота места под индекс рядом с концом линии.
const _chipRoom = 46.0;

/// Куда ставить индекс: растущий долг приходит к точке снизу — индекс над ней,
/// падающий приходит сверху — индекс под ней, чтобы линия не пряталась за плашкой.
bool trendChipAbove(DebtTrendDirection direction) => direction != DebtTrendDirection.down;

/// Точки линии в координатах карточки размером [size]. Старые дни — слева.
/// Над или под концом линии остаётся место для плашки с индексом ([chipAbove]).
List<Offset> trendOffsets(List<int> values, Size size, {bool chipAbove = true}) {
  if (values.length < 2) return const [];
  final left = size.width * trendStartFraction;
  final right = size.width - 22; // справа остаётся место под мигающую точку
  var top = size.height * 0.30;
  var bottom = size.height * 0.88;
  if (chipAbove) {
    top = math.max(top, _chipRoom);
  } else {
    bottom = math.min(bottom, size.height - _chipRoom);
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

/// Фон карточки: линия динамики общего долга, мигающая точка на конце и индекс в процентах.
class DebtTrendBackdrop extends StatefulWidget {
  const DebtTrendBackdrop({super.key, required this.trend});

  final DebtTrend trend;

  @override
  State<DebtTrendBackdrop> createState() => _DebtTrendBackdropState();
}

class _DebtTrendBackdropState extends State<DebtTrendBackdrop> with SingleTickerProviderStateMixin {
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
    final scheme = Theme.of(context).colorScheme;
    final trend = widget.trend;
    final color = trendColor(scheme, trend.direction);
    final text = formatTrendPercent(trend) ?? context.l10n.debtsTrendNew;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final chipAbove = trendChipAbove(trend.direction);
        final offsets = trendOffsets(trend.points, size, chipAbove: chipAbove);
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
            Positioned(
              right: 10,
              top: chipAbove ? null : end.dy + 12,
              bottom: chipAbove ? size.height - end.dy + 12 : null,
              child: Semantics(
                label: '$text, ${context.l10n.debtsTrendPeriod(trend.days)}',
                child: ExcludeSemantics(
                  child: _IndexChip(text: text, color: color, trend: trend),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IndexChip extends StatelessWidget {
  const _IndexChip({required this.text, required this.color, required this.trend});

  final String text;
  final Color color;
  final DebtTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (trend.direction) {
      DebtTrendDirection.up => Icons.trending_up_rounded,
      DebtTrendDirection.down => Icons.trending_down_rounded,
      DebtTrendDirection.flat => Icons.trending_flat_rounded,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 3),
                Text(
                  text,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Text(
              context.l10n.debtsTrendPeriod(trend.days),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  Path _linePath() {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      final a = offsets[i - 1], b = offsets[i];
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (offsets.length < 2) return;
    final fullLine = _linePath();
    final endX = offsets.last.dx;

    // Линия проявляется из прозрачности: заметна с 40% карточки и набирает силу к концу.
    final fade = LinearGradient(
      colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.9)],
      stops: const [0, 0.35],
    ).createShader(Rect.fromLTRB(startX, 0, endX, size.height));

    // Частично дорисованный путь.
    Path visible = fullLine;
    Offset tip = offsets.last;
    if (progress < 1) {
      visible = Path();
      final metrics = fullLine.computeMetrics().toList();
      final total = metrics.fold<double>(0, (s, PathMetric m) => s + m.length);
      var left = total * progress;
      for (final m in metrics) {
        if (left <= 0) break;
        visible.addPath(m.extractPath(0, math.min(left, m.length)), Offset.zero);
        left -= m.length;
      }
      final lastMetric = visible.computeMetrics().toList();
      tip = lastMetric.isEmpty
          ? offsets.first
          : (lastMetric.last.getTangentForOffset(lastMetric.last.length)?.position ??
                offsets.first);
    }

    // Заливка под линией: сверху вниз гаснет, а слева растворяется (маска dstIn).
    final bounds = Rect.fromLTRB(startX, 0, endX + 24, size.height);
    canvas.saveLayer(bounds, Paint());
    final area = Path.from(visible)
      ..lineTo(tip.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
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

    // Сама линия: заметна с 40% карточки, к концу набирает силу.
    canvas.drawPath(
      visible,
      Paint()
        ..shader = fade
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (progress < 1) return;
    // Медленно мигающая точка на конце линии.
    final t = Curves.easeInOut.transform(blink.value);
    final end = offsets.last;
    canvas.drawCircle(
      end,
      6 + 8 * t,
      Paint()..color = color.withValues(alpha: 0.28 * (1 - t) + 0.06),
    );
    canvas.drawCircle(end, 4.5, Paint()..color = color.withValues(alpha: 0.55 + 0.45 * (1 - t)));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.offsets != offsets ||
      old.color != color ||
      old.progress != progress ||
      old.startX != startX;
}
