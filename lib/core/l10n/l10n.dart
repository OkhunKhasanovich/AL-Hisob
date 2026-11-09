import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// Язык по умолчанию, если язык системы не поддерживается.
const defaultLocale = Locale('uz');

/// Названия языков на самих языках (не локализуются).
const languageNames = <String, String>{
  'uz': 'O‘zbekcha',
  'ru': 'Русский',
  'en': 'English',
  'kaa': 'Qaraqalpaqsha',
};

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Flutter не содержит Material/Cupertino-строк для каракалпакского (kaa).
/// Для системных надписей (кнопки диалогов, пикеры дат) берём русские,
/// а все строки приложения остаются каракалпакскими.
class _FallbackDelegate<T> extends LocalizationsDelegate<T> {
  const _FallbackDelegate(this.inner, this.fallback);

  final LocalizationsDelegate<T> inner;
  final Locale fallback;

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'kaa' || inner.isSupported(locale);

  @override
  Future<T> load(Locale locale) =>
      inner.load(locale.languageCode == 'kaa' ? fallback : locale);

  @override
  bool shouldReload(covariant _FallbackDelegate<T> old) => false;
}

const _fallbackLocale = Locale('ru');

final List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  const _FallbackDelegate<MaterialLocalizations>(
      GlobalMaterialLocalizations.delegate, _fallbackLocale),
  const _FallbackDelegate<WidgetsLocalizations>(
      GlobalWidgetsLocalizations.delegate, _fallbackLocale),
  const _FallbackDelegate<CupertinoLocalizations>(
      GlobalCupertinoLocalizations.delegate, _fallbackLocale),
];

/// Подбор языка: язык системы, если поддерживается, иначе [defaultLocale].
Locale resolveLocale(Locale? system, Iterable<Locale> supported) {
  if (system != null) {
    for (final l in supported) {
      if (l.languageCode == system.languageCode) return l;
    }
  }
  return defaultLocale;
}
