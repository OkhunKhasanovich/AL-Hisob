import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/l10n/l10n.dart';

void main() {
  test('поддерживаются uz, ru, en, kaa', () {
    final codes = AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(codes, {'uz', 'ru', 'en', 'kaa'});
  });

  test('язык системы подбирается, иначе uz', () {
    final supported = AppLocalizations.supportedLocales;
    expect(resolveLocale(const Locale('ru', 'RU'), supported).languageCode, 'ru');
    expect(resolveLocale(const Locale('de'), supported), defaultLocale);
    expect(resolveLocale(null, supported), defaultLocale);
  });

  testWidgets('каракалпакская локаль загружается вместе с системными строками', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('kaa'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));
    expect(captured.l10n.tabDebts, 'Qarızlar');
    expect(MaterialLocalizations.of(captured), isNotNull);
  });
}
