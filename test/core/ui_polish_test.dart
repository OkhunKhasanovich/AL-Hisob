import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/l10n/l10n.dart';
import 'package:al_savdogar/core/theme/app_theme.dart';
import 'package:al_savdogar/core/widgets/fade_slide_in.dart';
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
