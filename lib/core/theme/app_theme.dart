import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'glass_style.dart';
import 'theme_style.dart';

class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF1B6B50);

  static ThemeData light({ThemeStyle style = ThemeStyle.classic}) => _build(Brightness.light, style);
  static ThemeData dark({ThemeStyle style = ThemeStyle.classic}) => _build(Brightness.dark, style);

  static ThemeData _build(Brightness brightness, ThemeStyle style) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
    return style == ThemeStyle.liquidGlass ? _glass(base, brightness) : base;
  }

  /// Liquid Glass: страницы прозрачные (под ними фон страницы), карточки и поле поиска — стекло.
  static ThemeData _glass(ThemeData base, Brightness brightness) {
    final glass = GlassStyle.forBrightness(brightness);
    final rim = glass.rimNear.withValues(alpha: glass.rimNear.a * 0.6);
    return base.copyWith(
      extensions: [glass],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: glass.fill,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: rim),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(glass.fillStrong),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(StadiumBorder(side: BorderSide(color: rim))),
      ),
    );
  }
}
