import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../domain/update_info.dart';
import 'update_controller.dart';
import 'update_dialog.dart' show showUpdateDialog, updateErrorText;

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
            UpdatePhase.downloading => l10n.updateDownloading((state.progress * 100).round()),
            UpdatePhase.ready => l10n.updateReadyTitle,
            _ => null,
          };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.system_update_rounded),
      title: Text(l10n.updateTitle),
      subtitle: Text([version, ?status].join('\n')),
      isThreeLine: status != null,
      trailing: switch (state.phase) {
        UpdatePhase.checking => const SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
        UpdatePhase.downloading => SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: state.progress == 0 ? null : state.progress,
            ),
          ),
        UpdatePhase.ready =>
          Text(l10n.updateInstallButton, style: Theme.of(context).textTheme.labelLarge),
        _ => enabled
            ? Text(l10n.updateCheckButton, style: Theme.of(context).textTheme.labelLarge)
            : null,
      },
      onTap: !enabled || state.phase == UpdatePhase.checking || state.phase == UpdatePhase.downloading
          ? null
          : state.phase == UpdatePhase.ready
              // Скачано, но установку отложили: возвращаем предложение «Установить».
              ? () => showUpdateDialog(context)
              // Диалог при найденном обновлении откроет главный экран (HomeShell).
              : () => ref.read(updateControllerProvider.notifier).check(),
    );
  }
}
