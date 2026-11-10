import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'glass.dart';

/// Фон под стеклянными карточками. Стеклу нужно, что просвечивать: на ровном цвете
/// оно выглядит плоским, а на мягком цветном фоне оживает.
enum AppBackdropStyle {
  /// Мягкие цветные «облака», медленно плывущие по экрану, и тонкая узбекская
  /// геометрия (сетка восьмиконечных звёзд — как плитка на медресе) поверх них.
  ornament,

  /// Только плывущие цветные облака.
  aurora,

  /// Ровный фон без рисунка.
  plain,
}

/// Рисует фон выбранного стиля на весь экран; страницы поверх должны быть прозрачными.
class AppBackdrop extends StatefulWidget {
  const AppBackdrop({super.key, required this.style});

  final AppBackdropStyle style;

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop> {
  /// Время для дрейфа облаков. Меняется ~10 раз в секунду: движение медленное,
  /// а экран не перерисовывается 60 раз в секунду и не расходует батарею.
  final _time = ValueNotifier<double>(0);
  Timer? _timer;
  final _clock = Stopwatch();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        widget.style != AppBackdropStyle.plain && !MediaQuery.disableAnimationsOf(context);
    if (animate && _timer == null) {
      _clock.start();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _time.value = _clock.elapsedMilliseconds / 1000;
      });
    } else if (!animate) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didUpdateWidget(AppBackdrop old) {
    super.didUpdateWidget(old);
    didChangeDependencies();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == AppBackdropStyle.plain) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _AuroraPainter(
                time: _time,
                dark: dark,
                colors: [scheme.primary, GlassTint.blue, GlassTint.amber, GlassTint.purple],
              ),
            ),
          ),
          if (widget.style == AppBackdropStyle.ornament)
            // Узор не меняется: рисуется один раз, плавно гаснет к низу экрана.
            RepaintBoundary(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFF), Color(0x33FFFFFF)],
                ).createShader(rect),
                child: CustomPaint(
                  painter: _OrnamentPainter(
                    color: (dark ? Colors.white : scheme.primary).withValues(alpha: dark ? 0.07 : 0.10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.time, required this.dark, required this.colors})
      : super(repaint: time);

  final ValueListenable<double> time;
  final bool dark;
  final List<Color> colors;

  // Где облако «живёт» (доли экрана), размер и фаза дрейфа.
  static const _blobs = [
    (x: 0.08, y: 0.10, r: 0.85, phase: 0.0, period: 46.0),
    (x: 0.95, y: 0.34, r: 0.80, phase: 1.9, period: 58.0),
    (x: 0.05, y: 0.70, r: 0.75, phase: 3.7, period: 52.0),
    (x: 0.90, y: 0.95, r: 0.70, phase: 5.1, period: 64.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final alphas = dark ? const [0.34, 0.26, 0.14, 0.14] : const [0.26, 0.20, 0.16, 0.12];
    final reach = math.max(size.width, size.height);

    for (var i = 0; i < _blobs.length; i++) {
      final b = _blobs[i];
      final angle = 2 * math.pi * (t / b.period) + b.phase;
      final center = Offset(
        size.width * b.x + math.sin(angle) * size.width * 0.10,
        size.height * b.y + math.cos(angle * 0.8) * size.height * 0.05,
      );
      final radius = reach * b.r * 0.5;
      final color = colors[i % colors.length];
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alphas[i]), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.dark != dark || old.colors != colors;
}

/// Сетка восьмиконечных звёзд («хатам»): два наложенных квадрата, повёрнутых на 45°,
/// кольцо в центре и точки в узлах.
class _OrnamentPainter extends CustomPainter {
  _OrnamentPainter({required this.color});

  final Color color;

  static const tile = 64.0;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dot = Paint()..color = color;

    // Звезда: контур из 16 вершин, чередующих внешний и внутренний радиус.
    Path star(Offset c, double outer, double inner) {
      final path = Path();
      for (var i = 0; i < 16; i++) {
        final r = i.isEven ? outer : inner;
        final a = -math.pi / 2 + i * math.pi / 8;
        final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      return path..close();
    }

    final cols = (size.width / tile).ceil() + 1;
    final rows = (size.height / tile).ceil() + 1;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final c = Offset(col * tile + tile / 2, row * tile + tile / 2);
        canvas.drawPath(star(c, 26, 15), stroke);
        canvas.drawCircle(c, 6, stroke);
        // Точка в узле решётки между четырьмя звёздами.
        canvas.drawCircle(c + const Offset(tile / 2, tile / 2), 1.6, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_OrnamentPainter old) => old.color != color;
}
