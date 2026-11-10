import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/domain/sms_status.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../data/sms_providers.dart';
import 'sms_ui_helpers.dart';

/// «История SMS» в карточке должника.
class SmsLogSection extends ConsumerWidget {
  const SmsLogSection({super.key, required this.debtorId});

  final String debtorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final logs = ref.watch(smsLogsProvider(debtorId)).value ?? const <SmsLog>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.smsLogTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (logs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                l10n.smsLogEmpty,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          for (final log in logs) _SmsLogTile(log: log),
      ],
    );
  }
}

String _dateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${formatDate(t)} ${two(t.hour)}:${two(t.minute)}';
}

class _SmsLogTile extends StatelessWidget {
  const _SmsLogTile({required this.log});

  final SmsLog log;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (icon, color, label) = switch (log.status) {
      SmsStatus.sent => (Icons.check_circle_rounded, scheme.primary, l10n.smsStatusSent),
      SmsStatus.failed => (Icons.error_rounded, scheme.error, l10n.smsStatusFailed),
      SmsStatus.composerOpened =>
        (Icons.open_in_new_rounded, scheme.tertiary, l10n.smsStatusComposer),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(icon, color: color),
        title: Text(label, style: theme.textTheme.titleSmall),
        subtitle: Text('${_dateTime(log.createdAt)} · ${formatPhone(log.phone)}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(log.body),
          if (log.status == SmsStatus.failed) ...[
            const SizedBox(height: 8),
            Text(
              smsReasonText(l10n, log.error),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
