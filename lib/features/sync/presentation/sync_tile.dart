import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import 'sync_controller.dart';

/// Состояние синхронизации в «Ещё». Показывается только вошедшему пользователю.
class SyncTile extends ConsumerWidget {
  const SyncTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    if (s.phase == SyncPhase.off) return const SizedBox.shrink();
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    final (icon, color) = switch (s.phase) {
      SyncPhase.offline => (Icons.cloud_off_outlined, scheme.onSurfaceVariant),
      SyncPhase.error || SyncPhase.accountMismatch => (Icons.sync_problem_outlined, scheme.error),
      _ => (Icons.cloud_done_outlined, scheme.primary),
    };
    final text = switch (s.phase) {
      SyncPhase.syncing => l10n.syncRunning,
      SyncPhase.offline => l10n.syncOffline,
      SyncPhase.error => l10n.syncError,
      SyncPhase.accountMismatch => l10n.syncMismatch,
      _ when s.pending > 0 => l10n.syncPending(s.pending),
      _ when s.lastSyncedAt != null =>
        l10n.syncLastAt(DateFormat.Hm().format(s.lastSyncedAt!.toLocal())),
      _ => l10n.syncNever,
    };

    return ListTile(
      leading: s.phase == SyncPhase.syncing
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Icon(icon, color: color),
      title: Text(l10n.syncTitle),
      subtitle: Text(text),
      trailing: s.phase == SyncPhase.accountMismatch
          ? null
          : TextButton(
              onPressed: s.phase == SyncPhase.syncing
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).syncNow(),
              child: Text(l10n.syncNow),
            ),
    );
  }
}
