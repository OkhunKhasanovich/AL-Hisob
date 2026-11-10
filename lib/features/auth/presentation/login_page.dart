import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/phone.dart';
import 'telegram_login_controller.dart';

String loginFailureText(AppLocalizations l10n, LoginFailure f) => switch (f) {
      LoginFailure.network => l10n.loginErrorNetwork,
      LoginFailure.expired => l10n.loginErrorExpired,
      LoginFailure.server => l10n.loginErrorServer,
      LoginFailure.rateLimited => l10n.loginErrorRate,
      LoginFailure.cannotOpenTelegram => l10n.loginErrorNoTelegram,
      LoginFailure.botNotConfigured => l10n.loginErrorBot,
    };

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final TelegramLoginController _controller;

  @override
  void initState() {
    super.initState();
    // Берём контроллер сразу: после закрытия экрана `ref` использовать нельзя.
    _controller = ref.read(telegramLoginProvider.notifier);
  }

  @override
  void dispose() {
    // Закрыли экран — прекращаем ожидание (а не опрашиваем сервер в фоне).
    Future(() => _controller.reset());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(telegramLoginProvider);

    ref.listen(telegramLoginProvider, (previous, next) {
      if (next.phase == LoginPhase.success && previous?.phase != LoginPhase.success) {
        HapticFeedback.mediumImpact();
        final phone = formatPhone(next.user!.phone);
        final messenger = ScaffoldMessenger.of(context);
        context.pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.loginSuccess(phone))));
      }
    });

    final waiting = state.phase == LoginPhase.starting || state.phase == LoginPhase.waiting;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.telegram, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(l10n.loginIntro, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  l10n.loginHow,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (waiting) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  Text(l10n.loginWaiting, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  if (state.failure == LoginFailure.cannotOpenTelegram)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        loginFailureText(l10n, state.failure!),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: state.phase == LoginPhase.waiting ? _controller.openTelegram : null,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(l10n.loginOpenTelegram),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _controller.cancel, child: Text(l10n.cancelButton)),
                ] else ...[
                  if (state.phase == LoginPhase.failed && state.failure != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        loginFailureText(l10n, state.failure!),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _controller.start();
                    },
                    icon: const Icon(Icons.telegram),
                    label: Text(l10n.loginTelegramButton),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
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
