import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../auth/presentation/auth_controller.dart';

/// Второй шаг первого запуска: предложение войти через Telegram, чтобы данные не потерялись
/// и синхронизировались между телефонами. Можно отложить — приложение работает и без входа.
class OnboardingSignInPage extends ConsumerWidget {
  const OnboardingSignInPage({super.key});

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    // Экран входа закрывается сам после успеха; здесь дожидаемся его и смотрим на результат.
    await context.push<void>(Routes.login);
    if (!context.mounted) return;
    if (ref.read(authControllerProvider).value != null) context.go(Routes.debts);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget perk(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
            ],
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              children: [
                FadeSlideIn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(Icons.telegram, size: 44, color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.signInStepTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.signInStepSubtitle,
                        style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 150),
                  child: Column(
                    children: [
                      perk(Icons.shield_outlined, l10n.signInPerkSafe),
                      perk(Icons.devices_rounded, l10n.signInPerkDevices),
                      perk(Icons.cloud_sync_rounded, l10n.signInPerkOffline),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _signIn(context, ref),
                  icon: const Icon(Icons.telegram),
                  label: Text(l10n.loginTelegramButton),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go(Routes.debts),
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(l10n.signInStepLater),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
