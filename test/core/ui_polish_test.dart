import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/l10n/l10n.dart';
import 'package:al_savdogar/core/theme/app_theme.dart';
import 'package:al_savdogar/core/widgets/fade_slide_in.dart';
import 'package:al_savdogar/core/widgets/glass.dart';
import 'package:al_savdogar/core/widgets/section_app_bar.dart';

void main() {
  group('FadeSlideIn', () {
    testWidgets('enabled: появляется плавно (сначала невидим)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FadeSlideIn(child: Text('x'))));
      final fade = find.descendant(of: find.byType(FadeSlideIn), matching: find.byType(FadeTransition));
      expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    });

    testWidgets('enabled: false — сразу на месте, без прозрачности и сдвига', (tester) async {
      // Карточки, созданные при прокрутке, не должны «проявляться» с задержкой.
      await tester.pumpWidget(
        const MaterialApp(home: FadeSlideIn(enabled: false, child: Text('x'))),
      );
      expect(find.text('x'), findsOneWidget);
      for (final type in [FadeTransition, SlideTransition]) {
        expect(
          find.descendant(of: find.byType(FadeSlideIn), matching: find.byType(type)),
          findsNothing,
        );
      }
    });
  });

  group('GlassCard', () {
    testWidgets('полупрозрачная, без тени внутри, нажатие работает', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: GlassCard(
            tint: GlassTint.red,
            onTap: () => taps++,
            child: const Text('карточка'),
          ),
        ),
      ));

      // Основа полупрозрачная: фон приложения просвечивает сквозь карточку, как в шашках.
      final layers = find
          .descendant(of: find.byType(GlassCard), matching: find.byType(ColoredBox))
          .evaluate()
          .map((e) => (e.widget as ColoredBox).color);
      expect(layers, isNotEmpty);
      expect(layers.every((c) => c.a < 1), isTrue, reason: 'ни один слой не глушит фон');

      // Цветной тени нет: под прозрачной карточкой она просвечивала бы внутрь.
      final shadows = find
          .descendant(of: find.byType(GlassCard), matching: find.byType(DecoratedBox))
          .evaluate()
          .map((e) => (e.widget as DecoratedBox).decoration)
          .whereType<BoxDecoration>()
          .expand((d) => d.boxShadow ?? const <BoxShadow>[]);
      expect(shadows, isEmpty);

      await tester.tap(find.text('карточка'));
      expect(taps, 1);
    });

    testWidgets('светлая и тёмная темы рисуются без ошибок', (tester) async {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Column(children: [
              GlassCard(tint: GlassTint.green, child: Text('a')),
              GlassPanel(child: SizedBox(height: 40, width: 200)),
            ]),
          ),
        ));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('SectionAppBar', () {
    testWidgets('название приложения мелко, название раздела крупно; цвет не зависит от прокрутки',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: const Scaffold(appBar: SectionAppBar(title: 'Долги')),
      ));

      final app = tester.widget<Text>(find.text('AL-SAVDOGAR'));
      final section = tester.widget<Text>(find.text('Долги'));
      expect(section.style!.fontSize!, greaterThan(app.style!.fontSize!));

      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, Colors.transparent);
      expect(bar.surfaceTintColor, Colors.transparent);
      expect(bar.scrolledUnderElevation, 0);
    });
  });

}
