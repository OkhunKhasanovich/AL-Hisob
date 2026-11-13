import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../auth/presentation/auth_controller.dart';
import '../auth/presentation/login_prompt.dart' show serverConfiguredProvider;
import '../profile/profile_providers.dart';
import '../profile/shop_profile_form.dart';
import '../sync/presentation/sync_controller.dart';

/// Первый запуск: выбор роли и названия. Если сервер настроен, дальше предлагается войти через
/// Telegram, а тем, кто уже пользовался приложением, — сразу войти и подтянуть свои данные.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  /// Идёт загрузка данных аккаунта после входа.
  bool _restoring = false;

  /// «Уже пользовались»: вход, затем загрузка профиля и данных с сервера. Профиль нашёлся —
  /// сразу на главный экран, иначе остаёмся на форме (вход уже выполнен).
  Future<void> _signInAndRestore() async {
    HapticFeedback.selectionClick();
    await context.push<void>(Routes.login);
    if (!mounted || ref.read(authControllerProvider).value == null) return;

    setState(() => _restoring = true);
    final sync = ref.read(syncControllerProvider.notifier);
    await sync.syncNow();
    final profile = await ref.read(shopProfileRepositoryProvider).current();
    if (!mounted) return;
    if (profile != null) {
      context.go(Routes.debts);
      return;
    }
    final l10n = context.l10n;
    final synced = ref.read(syncControllerProvider).phase == SyncPhase.idle;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(synced ? l10n.onboardingRestoreEmpty : l10n.onboardingRestoreFailed)),
      );
  }

  /// После создания профиля: не вошли и сервер есть — предлагаем войти, иначе на главный экран.
  Future<void> _afterProfileCreated() async {
    final signedIn = (await ref.read(authControllerProvider.future)) != null;
    if (!mounted) return;
    final offerSignIn = ref.read(serverConfiguredProvider) && !signedIn;
    context.go(offerSignIn ? Routes.onboardingSignIn : Routes.debts);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canRestore =
        ref.watch(serverConfiguredProvider) && ref.watch(authControllerProvider).value == null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _restoring
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(l10n.onboardingRestoring, style: theme.textTheme.titleMedium),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    children: [
                      FadeSlideIn(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Hero(
                              tag: 'app-logo',
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Icon(Icons.storefront_rounded, size: 40, color: scheme.onPrimary),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              l10n.onboardingTitle,
                              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.onboardingSubtitle,
                              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 150),
                        child: ShopProfileForm(
                          submitLabel: l10n.continueButton,
                          onSubmit: (name, role) async {
                            await ref
                                .read(shopProfileRepositoryProvider)
                                .create(name: name, roles: {role});
                            await _afterProfileCreated();
                          },
                        ),
                      ),
                      if (canRestore) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          l10n.onboardingHaveAccount,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _signInAndRestore,
                          icon: const Icon(Icons.telegram),
                          label: Text(l10n.onboardingSignInRestore),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
