import 'package:flutter/material.dart';

/// Краски стиля Liquid Glass для светлой или тёмной темы. Лежит в `ThemeData.extensions`:
/// если расширения в теме нет, приложение выглядит как обычно.
@immutable
class GlassStyle extends ThemeExtension<GlassStyle> {
  const GlassStyle({
    required this.brightness,
    required this.fill,
    required this.fillStrong,
    required this.rimNear,
    required this.rimFar,
    required this.edge,
    required this.highlight,
    required this.baseTop,
    required this.baseBottom,
    required this.orbs,
  });

  /// Краски для [brightness].
  factory GlassStyle.forBrightness(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  static const dark = GlassStyle(
    brightness: Brightness.dark,
    fill: Color(0x1AFFFFFF),
    fillStrong: Color(0x29FFFFFF),
    rimNear: Color(0x73FFFFFF),
    rimFar: Color(0x14FFFFFF),
    edge: Color(0x00000000),
    highlight: Color(0x2EFFFFFF),
    baseTop: Color(0xFF071C19),
    baseBottom: Color(0xFF0A1022),
    orbs: [
      GlassOrb(Color(0xFF16D29C), 0.55, 0.10, 0.12, 0.62),
      GlassOrb(Color(0xFF2B9BFF), 0.50, 0.95, 0.38, 0.58),
      GlassOrb(Color(0xFF8A5CFF), 0.48, 0.06, 0.74, 0.60),
      GlassOrb(Color(0xFFFFA24D), 0.28, 0.92, 0.98, 0.50),
    ],
  );

  static const light = GlassStyle(
    brightness: Brightness.light,
    fill: Color(0x73FFFFFF),
    fillStrong: Color(0xA6FFFFFF),
    rimNear: Color(0xF2FFFFFF),
    rimFar: Color(0x66FFFFFF),
    edge: Color(0x14000000),
    highlight: Color(0x99FFFFFF),
    baseTop: Color(0xFFE4F6EE),
    baseBottom: Color(0xFFE6EBFA),
    orbs: [
      GlassOrb(Color(0xFF63D8AE), 0.80, 0.10, 0.12, 0.62),
      GlassOrb(Color(0xFF7DBDFF), 0.75, 0.95, 0.38, 0.58),
      GlassOrb(Color(0xFFBBA0FF), 0.65, 0.06, 0.74, 0.60),
      GlassOrb(Color(0xFFFFC796), 0.55, 0.92, 0.98, 0.50),
    ],
  );

  /// Стиль из темы; `null` — тема обычная.
  static GlassStyle? maybeOf(BuildContext context) => Theme.of(context).extension<GlassStyle>();

  final Brightness brightness;

  /// Заливка обычных поверхностей (карточки): сквозь неё виден цветной фон.
  final Color fill;

  /// Заливка поверхностей с размытием (панель вкладок, поиск): плотнее, чтобы текст под ними не мешал.
  final Color fillStrong;

  /// Кромка стекла у освещённого угла (слева сверху) и у дальнего.
  final Color rimNear;
  final Color rimFar;

  /// Тонкий тёмный контур (нужен на светлом фоне, где белая кромка не видна).
  final Color edge;

  /// Блик у освещённого угла.
  final Color highlight;

  /// Фон: вертикальный градиент и цветные «шары» поверх него.
  final Color baseTop;
  final Color baseBottom;
  final List<GlassOrb> orbs;

  @override
  GlassStyle copyWith({Brightness? brightness}) =>
      brightness == null || brightness == this.brightness ? this : GlassStyle.forBrightness(brightness);

  @override
  GlassStyle lerp(ThemeExtension<GlassStyle>? other, double t) => t < 0.5 ? this : (other as GlassStyle? ?? this);
}

/// Цветной «шар» фона: цвет, сила, положение центра (доли экрана) и радиус (доля большей стороны).
@immutable
class GlassOrb {
  const GlassOrb(this.color, this.opacity, this.x, this.y, this.radius);

  final Color color;
  final double opacity;
  final double x;
  final double y;
  final double radius;
}
