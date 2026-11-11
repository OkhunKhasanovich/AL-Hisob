import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Оттенки подсветки стекла. Карточка берёт оттенок по своему состоянию
/// (как турниры в шашках: активный — зелёный, закрытый — красный и т. д.).
abstract final class GlassTint {
  static const blue = Color(0xFF5A96FF);
  static const green = Color(0xFF28C88C);
  static const amber = Color(0xFFF5A028);
  static const red = Color(0xFFEB5050);
  static const purple = Color(0xFFAA64FF);
  static const gray = Color(0xFF9696A0);
}

/// Основа стеклянных поверхностей: в тёмной теме — настоящий чёрный с прозрачностью (как карточки
/// в шашках), в светлой — белый. Через неё просвечивает фон приложения.
Color glassBase(Brightness brightness, {double opacity = 0.62}) =>
    (brightness == Brightness.dark ? Colors.black : Colors.white).withValues(alpha: opacity);

/// Карточка «матовое стекло». Рецепт:
/// 1. подложка цвета поверхности;
/// 2. диагональная заливка оттенком (плотнее в углу, к другому краю гаснет);
/// 3. светлый блик сверху слева;
/// 4. тонкая рамка и светлая «кромка» по верхнему краю;
/// 5. наклонная полоса-отсвет и мягкая цветная тень снизу.
///
/// В тёмной теме всё спокойнее: меньше света в оттенке и блике.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.tint = GlassTint.blue,
    this.radius = 20,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.opacity,
  });

  final Widget child;
  final Color tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  /// Насколько карточка «заслоняет» фон под собой, 0…1. По умолчанию в тёмной теме около
  /// половины (тёмное полупрозрачное стекло, узор фона просвечивает, текст читается),
  /// в светлой — чуть плотнее.
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);

    // Основа полупрозрачная: сквозь неё виден фон приложения. Тёмная — чтобы светлый текст
    // читался даже на ярком облаке, светлая — для тёмного текста.
    final base = glassBase(theme.brightness, opacity: opacity ?? 0.62);
    // В тёмной теме оттенок едва заметен: карточка остаётся чёрной, а состояние читается
    // по цвету рамки и значков.
    final tintTop = tint.withValues(alpha: dark ? 0.13 : 0.26);
    final tintMid = tint.withValues(alpha: dark ? 0.02 : 0.06);
    final highlight = Colors.white.withValues(alpha: dark ? 0.04 : 0.20);
    final highlightEnd = Colors.white.withValues(alpha: dark ? 0 : 0.03);
    final border = tint.withValues(alpha: dark ? 0.40 : 0.38);

    return Padding(
      padding: margin,
      child: DecoratedBox(
        // Цветной тени снизу нет: под полупрозрачной карточкой она просвечивала бы внутрь.
        decoration: BoxDecoration(borderRadius: borderRadius),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            children: [
              // 1. Полупрозрачная основа. (Цвет и градиент в одном BoxDecoration не накладываются,
              // поэтому основа — отдельным слоем.)
              Positioned.fill(child: ColoredBox(color: base)),
              // 2. Оттенок.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tintTop, tintMid],
                      stops: const [0, 0.7],
                    ),
                  ),
                ),
              ),
              // 3. Блик.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [highlight, highlightEnd, Colors.white.withValues(alpha: 0)],
                      stops: const [0, 0.52, 1],
                    ),
                  ),
                ),
              ),
              // 5. Наклонная полоса-отсвет справа.
              Positioned.fill(
                child: IgnorePointer(
                  child: LayoutBuilder(
                    builder: (context, c) => OverflowBox(
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      alignment: Alignment.topRight,
                      child: Transform.translate(
                        offset: Offset(c.maxWidth * 0.2, -c.maxHeight * 0.4),
                        child: Transform.rotate(
                          angle: 20 * math.pi / 180,
                          child: Container(
                            width: c.maxWidth * 0.55,
                            height: c.maxHeight * 1.4,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: dark ? 0.05 : 0.10),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Содержимое и нажатие.
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: borderRadius,
                  onTap: onTap,
                  child: Padding(padding: padding, child: child),
                ),
              ),
              // 4. Рамка и светлая кромка сверху.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(color: border),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: radius * 0.6,
                right: radius * 0.6,
                height: 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: dark ? 0.28 : 0.55),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плоская «стеклянная» панель с размытием того, что под ней (нижняя панель вкладок, шапки).
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.radius = 28, this.blur = 20});

  final Widget child;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      // Без тени: под полупрозрачной панелью она просвечивала бы внутрь.
      decoration: BoxDecoration(borderRadius: borderRadius),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: ColoredBox(
            color: glassBase(theme.brightness, opacity: dark ? 0.66 : 0.72),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.05 : 0.35),
                    Colors.white.withValues(alpha: dark ? 0 : 0.05),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.5)),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
