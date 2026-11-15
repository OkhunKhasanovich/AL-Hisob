import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/glass_style.dart';

/// Фон Liquid Glass: глубокий градиент и мягкие цветные «шары». Стеклу нужно, что просвечивать:
/// на ровном цвете оно плоское. Рисуется один раз (без анимации), поэтому батарею не тратит.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final style = GlassStyle.maybeOf(context) ?? GlassStyle.forBrightness(Theme.of(context).brightness);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('glass-backdrop'),
          painter: _BackdropPainter(style),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.style);

  final GlassStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [style.baseTop, style.baseBottom],
        ).createShader(rect),
    );
    final longest = size.longestSide;
    for (final orb in style.orbs) {
      final center = Offset(size.width * orb.x, size.height * orb.y);
      final radius = longest * orb.radius * 0.5;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [orb.color.withValues(alpha: orb.opacity), orb.color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.style != style;
}

/// Оборачивает страницу: в стиле Liquid Glass подкладывает под неё фон (страницы в этом стиле прозрачные),
/// в обычном ничего не меняет. Свой фон у каждой страницы нужен, чтобы при переходах
/// одна страница не просвечивала сквозь другую.
class GlassPage extends StatelessWidget {
  const GlassPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (GlassStyle.maybeOf(context) == null) return child;
    return Stack(fit: StackFit.expand, children: [const GlassBackdrop(), child]);
  }
}

/// Стеклянная поверхность: полупрозрачная заливка с диагональным градиентом, блик у освещённого
/// угла и кромка, которая светлее слева сверху. [blur] > 0 размывает то, что лежит под поверхностью
/// (для панелей, под которыми прокручивается содержимое); у карточек списка его нет — их много,
/// а под ними гладкий фон.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = 0,
    this.strong = false,
    this.tint,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;

  /// Плотная заливка (панели).
  final bool strong;

  /// Лёгкий цветной оттенок стекла (например, цвет акцента).
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = GlassStyle.maybeOf(context) ?? GlassStyle.forBrightness(Theme.of(context).brightness);
    Widget content = Material(
      type: MaterialType.transparency,
      child: onTap == null
          ? (padding == null ? child : Padding(padding: padding!, child: child))
          : InkWell(
              borderRadius: borderRadius,
              onTap: onTap,
              child: padding == null ? child : Padding(padding: padding!, child: child),
            ),
    );
    content = CustomPaint(
      painter: _SurfacePainter(style, borderRadius, strong: strong, tint: tint),
      foregroundPainter: _RimPainter(style, borderRadius),
      child: content,
    );
    return ClipRRect(
      borderRadius: borderRadius,
      child: blur > 0 ? BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: content) : content,
    );
  }
}

class _SurfacePainter extends CustomPainter {
  _SurfacePainter(this.style, this.radius, {required this.strong, this.tint});

  final GlassStyle style;
  final BorderRadius radius;
  final bool strong;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    final base = strong ? style.fillStrong : style.fill;

    // Заливка: у освещённого угла плотнее, к дальнему краю прозрачнее.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, base.withValues(alpha: base.a * 0.72)],
        ).createShader(rect),
    );
    if (tint != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint!.withValues(alpha: 0.20), tint!.withValues(alpha: 0.04)],
          ).createShader(rect),
      );
    }
    // Блик: мягкое пятно света у верхнего левого угла.
    canvas.save();
    canvas.clipRRect(rrect);
    final glowRadius = size.shortestSide * 1.1;
    canvas.drawCircle(
      rect.topLeft,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [style.highlight, style.highlight.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: rect.topLeft, radius: glowRadius)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SurfacePainter old) =>
      old.style != style || old.radius != radius || old.strong != strong || old.tint != tint;
}

/// Кромка поверх содержимого: светлая у освещённого угла, к противоположному тает; на светлом фоне
/// добавляется тонкий тёмный контур.
class _RimPainter extends CustomPainter {
  _RimPainter(this.style, this.radius);

  final GlassStyle style;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.6);
    if (style.edge.a > 0) {
      canvas.drawRRect(
        radius.toRRect(rect).deflate(0.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = style.edge,
      );
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.rimNear, style.rimFar, style.rimNear.withValues(alpha: style.rimNear.a * 0.35)],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.style != style || old.radius != radius;
}
