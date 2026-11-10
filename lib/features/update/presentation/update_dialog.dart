import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import 'update_controller.dart';

/// Диалог «Доступно обновление»: сам следует за состоянием контроллера
/// (предложение → скачивание → разрешение/ошибка).
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const UpdateDialog(),
  );
}

String updateErrorText(AppLocalizations l10n, UpdateErrorKind? kind) => switch (kind) {
      UpdateErrorKind.check => l10n.updateErrorCheck,
      UpdateErrorKind.download => l10n.updateErrorDownload,
      UpdateErrorKind.verify => l10n.updateErrorVerify,
      UpdateErrorKind.install => l10n.updateErrorInstall,
      null => l10n.updateErrorCheck,
    };

class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final info = state.info;

    // Состояние сброшено (установка запущена, «Позже», «Пропустить») — закрываем.
    if (state.phase == UpdatePhase.idle || state.phase == UpdatePhase.upToDate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    switch (state.phase) {
      case UpdatePhase.downloading:
        final percent = (state.progress * 100).round();
        return PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(Icons.downloading_rounded),
            title: Text(l10n.updateDownloading(percent)),
            content: LinearProgressIndicator(value: state.progress == 0 ? null : state.progress),
          ),
        );

      case UpdatePhase.needsPermission:
        return AlertDialog(
          icon: const Icon(Icons.security_update_good_rounded),
          title: Text(l10n.updatePermissionTitle),
          content: Text(l10n.updatePermissionBody),
          actions: [
            TextButton(onPressed: controller.dismiss, child: Text(l10n.updateLater)),
            TextButton(
              onPressed: controller.openInstallSettings,
              child: Text(l10n.openSettingsButton),
            ),
            FilledButton(onPressed: controller.install, child: Text(l10n.updateButton)),
          ],
        );

      case UpdatePhase.error:
        return AlertDialog(
          icon: const Icon(Icons.error_outline_rounded),
          title: Text(l10n.updateAvailableTitle),
          content: Text(updateErrorText(l10n, state.errorKind)),
          actions: [
            TextButton(onPressed: controller.dismiss, child: Text(l10n.closeButton)),
            if (info != null)
              FilledButton(onPressed: controller.install, child: Text(l10n.updateRetry)),
          ],
        );

      case UpdatePhase.available:
      case UpdatePhase.checking:
      case UpdatePhase.idle:
      case UpdatePhase.upToDate:
        return AlertDialog(
          icon: const Icon(Icons.system_update_rounded),
          title: Text(l10n.updateAvailableTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info != null) Text(l10n.updateAvailableBody(info.versionName, info.build)),
                if (info?.notes != null) ...[
                  const SizedBox(height: 12),
                  Text(info!.notes!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: controller.skip, child: Text(l10n.updateSkip)),
            TextButton(onPressed: controller.dismiss, child: Text(l10n.updateLater)),
            FilledButton(onPressed: controller.install, child: Text(l10n.updateButton)),
          ],
        );
    }
  }
}
