import 'package:flutter/material.dart';

import '../../../core/domain/order_status.dart';
import '../../../core/l10n/l10n.dart';
import '../domain/order_workflow.dart';

String statusLabel(AppLocalizations l10n, OrderStatus s) => switch (s) {
      OrderStatus.created => l10n.orderStatusCreated,
      OrderStatus.accepted => l10n.orderStatusAccepted,
      OrderStatus.picking => l10n.orderStatusPicking,
      OrderStatus.ready => l10n.orderStatusReady,
      OrderStatus.inTransit => l10n.orderStatusInTransit,
      OrderStatus.delivered => l10n.orderStatusDelivered,
      OrderStatus.closed => l10n.orderStatusClosed,
      OrderStatus.rejected => l10n.orderStatusRejected,
      OrderStatus.cancelled => l10n.orderStatusCancelled,
    };

String groupLabel(AppLocalizations l10n, OrderGroup g) => switch (g) {
      OrderGroup.all => l10n.filterAll,
      OrderGroup.fresh => l10n.orderGroupFresh,
      OrderGroup.inProgress => l10n.orderGroupInProgress,
      OrderGroup.delivered => l10n.orderGroupDelivered,
      OrderGroup.closed => l10n.orderGroupClosed,
      OrderGroup.cancelled => l10n.orderGroupCancelled,
    };

IconData statusIcon(OrderStatus s) => switch (s) {
      OrderStatus.created => Icons.fiber_new_rounded,
      OrderStatus.accepted => Icons.thumb_up_alt_rounded,
      OrderStatus.picking => Icons.inventory_rounded,
      OrderStatus.ready => Icons.local_shipping_outlined,
      OrderStatus.inTransit => Icons.local_shipping_rounded,
      OrderStatus.delivered => Icons.where_to_vote_rounded,
      OrderStatus.closed => Icons.check_circle_rounded,
      OrderStatus.rejected => Icons.block_rounded,
      OrderStatus.cancelled => Icons.cancel_rounded,
    };

/// Цвет статуса: проблемные (отклонён/отменён) — тревожным, завершённые — спокойным.
({Color background, Color foreground}) statusColors(ColorScheme c, OrderStatus s) => switch (s) {
      OrderStatus.rejected || OrderStatus.cancelled =>
        (background: c.errorContainer, foreground: c.onErrorContainer),
      OrderStatus.delivered || OrderStatus.closed =>
        (background: c.primaryContainer, foreground: c.onPrimaryContainer),
      OrderStatus.created => (background: c.tertiaryContainer, foreground: c.onTertiaryContainer),
      _ => (background: c.secondaryContainer, foreground: c.onSecondaryContainer),
    };

/// Плашка статуса.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = statusColors(Theme.of(context).colorScheme, status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon(status), size: 16, color: colors.foreground),
            const SizedBox(width: 4),
            Text(
              statusLabel(context.l10n, status),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.foreground),
            ),
          ],
        ),
      ),
    );
  }
}
