import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/domain/order_status.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_input_formatter.dart';
import '../../catalog/presentation/product_labels.dart';
import '../../profile/shop_name.dart';
import '../data/orders_providers.dart';
import '../domain/order_models.dart';
import '../domain/order_workflow.dart';
import 'order_labels.dart';

class OrderDetailsPage extends ConsumerWidget {
  const OrderDetailsPage({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(orderDetailsProvider(orderId));
    return details.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (d) => d == null ? Scaffold(appBar: AppBar()) : _Content(details: d),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.details});

  final OrderDetails details;

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    OrderStatus to, {
    String? note,
  }) async {
    HapticFeedback.mediumImpact();
    await ref.read(ordersRepositoryProvider).changeStatus(
          details.order.id,
          to,
          actorName: readShopName(ref, context),
          note: note,
        );
  }

  /// Отклонение/отмена: подтверждение и необязательная причина.
  Future<void> _confirmWithReason(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required OrderStatus to,
  }) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title),
    );
    if (note != null && context.mounted) await _change(context, ref, to, note: note);
  }

  Future<void> _deliver(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final paid = await showDialog<int>(
      context: context,
      builder: (_) => _DeliverDialog(total: details.order.total),
    );
    if (paid == null || !context.mounted) return;
    HapticFeedback.mediumImpact();
    final actor = readShopName(ref, context);
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(ordersRepositoryProvider)
        .deliver(details.order.id, paidAmount: paid, actorName: actor);
    if (paid < details.order.total) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.orderDebtRecorded)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final order = details.order;
    watchShopName(ref, context); // подписка на профиль: имя автора в истории

    final actions = <Widget>[
      ..._primaryActions(context, ref, l10n),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.orderNumberTitle(order.number))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(children: [StatusChip(status: order.status)]),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
              title: Text(details.customerName),
              subtitle: Text(l10n.orderCustomerLabel),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.debtorDetails(order.customerId)),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...actions,
          ],
          const SizedBox(height: 20),
          Text(l10n.orderItemsTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final i in details.items) _ItemRow(item: i),
          const Divider(height: 24),
          _SumRow(label: l10n.orderTotalLabel, value: order.total, bold: true),
          if (order.paidAmount > 0 || order.status == OrderStatus.delivered || order.status == OrderStatus.closed) ...[
            _SumRow(label: l10n.orderPaidLabel, value: order.paidAmount),
            _SumRow(
              label: l10n.orderRemainingLabel,
              value: details.remaining,
              color: details.remaining > 0 ? scheme.error : null,
            ),
          ],
          if (order.comment != null) ...[
            const SizedBox(height: 16),
            Text(order.comment!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          Text(l10n.orderHistoryTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _History(history: details.history),
        ],
      ),
    );
  }

  List<Widget> _primaryActions(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final s = details.order.status;
    final next = nextStatuses(s);

    FilledButton primary(String label, IconData icon, VoidCallback onTap) => FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        );

    OutlinedButton secondary(String label, IconData icon, VoidCallback onTap, {bool danger = false}) =>
        OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: danger ? Theme.of(context).colorScheme.error : null,
          ),
        );

    final widgets = <Widget>[];
    switch (s) {
      case OrderStatus.created:
        widgets.add(primary(l10n.orderActionAccept, Icons.check_rounded,
            () => _change(context, ref, OrderStatus.accepted)));
      case OrderStatus.accepted:
        widgets.add(primary(l10n.orderActionStartPicking, Icons.inventory_rounded,
            () => _change(context, ref, OrderStatus.picking)));
      case OrderStatus.picking:
        widgets.add(primary(l10n.orderActionMarkReady, Icons.fact_check_rounded,
            () => _change(context, ref, OrderStatus.ready)));
      case OrderStatus.ready:
        widgets.add(primary(l10n.orderActionShip, Icons.local_shipping_rounded,
            () => _change(context, ref, OrderStatus.inTransit)));
      case OrderStatus.inTransit:
        widgets.add(primary(l10n.orderActionDeliver, Icons.where_to_vote_rounded,
            () => _deliver(context, ref)));
      case OrderStatus.delivered:
        widgets.add(primary(l10n.orderActionClose, Icons.check_circle_rounded,
            () => _change(context, ref, OrderStatus.closed)));
      case OrderStatus.closed || OrderStatus.rejected || OrderStatus.cancelled:
        break;
    }

    if (canEditItems(s)) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(secondary(l10n.orderActionEdit, Icons.edit_rounded,
          () => context.push(Routes.orderEdit(details.order.id))));
    }
    if (next.contains(OrderStatus.rejected)) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(secondary(l10n.orderActionReject, Icons.block_rounded,
          () => _confirmWithReason(context, ref, title: l10n.orderRejectTitle, to: OrderStatus.rejected),
          danger: true));
    }
    if (next.contains(OrderStatus.cancelled)) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(secondary(l10n.orderActionCancel, Icons.cancel_outlined,
          () => _confirmWithReason(context, ref, title: l10n.orderCancelTitle, to: OrderStatus.cancelled),
          danger: true));
    }
    return widgets;
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final unit = unitLabel(l10n, item.unit);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: theme.textTheme.titleSmall),
                Text(
                  '${formatAmount(item.quantity)} $unit × ${formatAmount(item.unitPrice)} ${l10n.currencySum}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${formatAmount(item.lineTotal)} ${l10n.currencySum}',
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow({required this.label, required this.value, this.bold = false, this.color});

  final String label;
  final int value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = (bold ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.titleMedium)
        ?.copyWith(fontWeight: bold ? FontWeight.w700 : null, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text('${formatAmount(value)} ${l10n.currencySum}', style: style),
        ],
      ),
    );
  }
}

String _dateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${formatDate(t)} ${two(t.hour)}:${two(t.minute)}';
}

/// Шкала истории: кто и когда менял статус или состав заказа (новые сверху).
class _History extends StatelessWidget {
  const _History({required this.history});

  final List<OrderStatusHistoryData> history;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = history.reversed.toList();

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      Icon(
                        entries[i].isEdit ? Icons.edit_rounded : statusIcon(entries[i].status),
                        size: 20,
                        color: i == 0 ? scheme.primary : scheme.outline,
                      ),
                      if (i < entries.length - 1)
                        Expanded(child: VerticalDivider(width: 2, thickness: 2, color: scheme.outlineVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entries[i].isEdit ? l10n.orderEdited : statusLabel(l10n, entries[i].status),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          '${_dateTime(entries[i].createdAt)} · ${entries[i].actorName}',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (entries[i].note != null)
                          Text(entries[i].note!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Подтверждение с необязательной причиной. Возвращает текст причины (может быть пустым)
/// или `null`, если пользователь отказался. Контроллер живёт внутри диалога: освобождать
/// его снаружи сразу после закрытия нельзя — анимация закрытия ещё использует поле.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        maxLength: 200,
        decoration: InputDecoration(labelText: l10n.orderReasonLabel),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.deleteButton),
        ),
      ],
    );
  }
}

/// Диалог доставки: сколько получено; остаток запишется долгом в книгу.
class _DeliverDialog extends StatefulWidget {
  const _DeliverDialog({required this.total});

  final int total;

  @override
  State<_DeliverDialog> createState() => _DeliverDialogState();
}

class _DeliverDialogState extends State<_DeliverDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: formatAmount(widget.total))..addListener(() => setState(() {}));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Введённая сумма; пустое поле = 0.
  int get _paid => parseAmount(_controller.text) ?? 0;

  bool get _tooBig => _paid > widget.total;

  void _set(int value) {
    final text = value == 0 ? '' : formatAmount(value);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final remaining = widget.total - _paid;

    return AlertDialog(
      title: Text(l10n.orderDeliverTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.orderTotalLabel}: ${formatAmount(widget.total)} ${l10n.currencySum}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.orderPaidFull),
                selected: _paid == widget.total,
                onSelected: (_) => _set(widget.total),
              ),
              ChoiceChip(
                label: Text(l10n.orderOnCredit),
                selected: _paid == 0,
                onSelected: (_) => _set(0),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [AmountInputFormatter()],
            decoration: InputDecoration(
              labelText: l10n.orderReceivedLabel,
              suffixText: l10n.currencySum,
              errorText: _tooBig ? l10n.orderAmountTooBig : null,
            ),
          ),
          const SizedBox(height: 8),
          if (!_tooBig)
            Text(
              remaining > 0
                  ? l10n.orderDebtHint('${formatAmount(remaining)} ${l10n.currencySum}')
                  : l10n.orderFullyPaidHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: remaining > 0 ? theme.colorScheme.error : theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: _tooBig ? null : () => Navigator.pop(context, _paid),
          child: Text(l10n.orderActionDeliver),
        ),
      ],
    );
  }
}
