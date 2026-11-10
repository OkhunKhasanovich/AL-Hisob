import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../domain/update_info.dart';
import 'update_controller.dart';
import 'update_dialog.dart' show updateErrorText;

/// Плитка «Обновление приложения» во вкладке «Ещё»: версия и ручная проверка.
class UpdateTile extends ConsumerWidget {
  const UpdateTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final build = ref.watch(currentBuildProvider);
    final state = ref.watch(updateControllerProvider);
    final enabled = build > 0;

    final version = l10n.updateVersionLine(appVersionName, build);
    final status = !enabled
        ? l10n.updateDevBuild
        : switch (state.phase) {
            UpdatePhase.checking => l10n.updateChecking,
            UpdatePhase.upToDate => l10n.updateUpToDate,
            UpdatePhase.error => updateErrorText(l10n, state.errorKind),
            UpdatePhase.available => l10n.updateAvailableTitle,
            _ => null,
          };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.system_update_rounded),
      title: Text(l10n.updateTitle),
      subtitle: Text([version, ?status].join('\n')),
      isThreeLine: status != null,
      trailing: state.phase == UpdatePhase.checking
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
          : (enabled ? Text(l10n.updateCheckButton, style: Theme.of(context).textTheme.labelLarge) : null),
      onTap: !enabled || state.phase == UpdatePhase.checking
          ? null
          // Диалог при найденном обновлении откроет главный экран (HomeShell).
          : () => ref.read(updateControllerProvider.notifier).check(),
    );
  }
}
