import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF1B6B50);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        // Только значки; название вкладки остаётся в подсказке и для экранных дикторов.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        indicatorColor: scheme.secondaryContainer,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
