import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/phone.dart';
import 'login_prompt.dart';
import 'auth_controller.dart';

/// Блок «Аккаунт» во вкладке «Ещё»: войти или выйти. Скрыт, если сервер не настроен.
class AccountTile extends ConsumerWidget {
  const AccountTile({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.accountSignOutTitle),
        content: Text(l10n.accountSignOutBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.accountSignOut)),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(serverConfiguredProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final user = auth.value?.user;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(user == null ? Icons.account_circle_outlined : Icons.account_circle_rounded),
      title: Text(l10n.accountTitle),
      subtitle: Text(
        user == null ? l10n.accountSignedOut : l10n.accountSignedInAs(formatPhone(user.phone)),
      ),
      trailing: auth.isLoading
          ? null
          : (user == null
              ? FilledButton(
                  onPressed: () => context.push(Routes.login),
                  child: Text(l10n.accountSignIn),
                )
              : TextButton(
                  onPressed: () => _confirmSignOut(context, ref),
                  child: Text(l10n.accountSignOut),
                )),
    );
  }
}
