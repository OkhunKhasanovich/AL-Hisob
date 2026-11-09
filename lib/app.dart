import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/l10n.dart';
import 'core/router/app_router.dart';
import 'core/settings/settings_providers.dart';
import 'core/theme/app_theme.dart';

class AlSavdogarApp extends ConsumerStatefulWidget {
  const AlSavdogarApp({super.key, this.router});

  /// Для тестов можно подставить свой роутер.
  final GoRouter? router;

  @override
  ConsumerState<AlSavdogarApp> createState() => _AlSavdogarAppState();
}

class _AlSavdogarAppState extends ConsumerState<AlSavdogarApp> {
  late final GoRouter _router = widget.router ?? createRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      localeResolutionCallback: (locale, supported) => resolveLocale(locale, supported),
      routerConfig: _router,
    );
  }
}
