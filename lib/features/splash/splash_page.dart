import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/router/routes.dart';
import '../profile/profile_providers.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key, this.duration = const Duration(milliseconds: 1800)});

  /// Сколько показывать splash до перехода на главный экран.
  final Duration duration;

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final Animation<double> _logoScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.7, curve: Curves.elasticOut),
  );
  late final Animation<double> _textFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 1, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _routeAfterSplash();
  }

  /// Профиль есть — на главный экран, иначе — на онбординг.
  Future<void> _routeAfterSplash() async {
    final results = await Future.wait<Object?>([
      Future<void>.delayed(widget.duration),
      ref.read(shopProfileRepositoryProvider).current(),
    ]);
    if (!mounted) return;
    context.go(results.last == null ? Routes.onboarding : Routes.debts);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.surface],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _logoScale,
                child: Hero(
                  tag: 'app-logo',
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Icon(Icons.storefront_rounded, size: 60, color: scheme.onPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: _textFade,
                child: Column(
                  children: [
                    Text(
                      context.l10n.appName,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.splashTagline,
                      style: textTheme.bodyLarge?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
