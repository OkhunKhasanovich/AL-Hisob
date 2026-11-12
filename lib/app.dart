import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/l10n.dart';
import 'core/router/app_router.dart';
import 'core/settings/settings_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/sync/presentation/sync_controller.dart';

class AlHisobApp extends ConsumerStatefulWidget {
  const AlHisobApp({super.key, this.router});

  /// Для тестов можно подставить свой роутер.
  final GoRouter? router;

  @override
  ConsumerState<AlHisobApp> createState() => _AlHisobAppState();
}

class _AlHisobAppState extends ConsumerState<AlHisobApp> {
  late final GoRouter _router = widget.router ?? createRouter();

  @override
  Widget build(BuildContext context) {
    // Фоновая синхронизация живёт всё время работы приложения; на перерисовку она не влияет.
    ref.listen(syncControllerProvider, (_, _) {});
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
