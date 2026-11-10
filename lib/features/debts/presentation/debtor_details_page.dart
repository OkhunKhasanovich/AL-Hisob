import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/domain/debt_kind.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../data/debtors_repository.dart';
import '../domain/debt_summary.dart';
import 'balance_style.dart';
import 'debtor_avatar.dart';
import 'debts_providers.dart';
import 'transaction_sheet.dart';

class DebtorDetailsPage extends ConsumerWidget {
  const DebtorDetailsPage({super.key, required this.debtorId});

  final String debtorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(debtorDetailsProvider(debtorId));
    return details.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      // null — должник удалён: экран уже закрывается.
      data: (d) => d == null
          ? Scaffold(appBar: AppBar())
          : _DetailsContent(details: d),
    );
  }
}

class _DetailsContent extends ConsumerWidget {
  const _DetailsContent({required this.details});

  final DebtorDetails details;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final repo = ref.read(debtorsRepositoryProvider);
    final id = details.summary.debtor.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteDebtorTitle),
        content: Text(l10n.deleteDebtorBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.deleteButton)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    context.pop(); // сначала закрываем экран, потом удаляем
    await repo.deleteDebtor(id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final summary = details.summary;
    final d = summary.debtor;

    return Scaffold(
      appBar: AppBar(
        title: Text(d.name),
        actions: [
          IconButton(
            tooltip: l10n.editButton,
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push(Routes.debtorEdit(d.id)),
          ),
          IconButton(
            tooltip: l10n.deleteButton,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  DebtorAvatar(id: d.id, name: d.name, radius: 32),
                  const SizedBox(height: 16),
                  Text(l10n.balanceLabel, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      balanceText(l10n, summary.balance),
                      key: ValueKey(summary.balance),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: balanceColor(theme.colorScheme, summary.balance),
                      ),
                    ),
                  ),
                  if (summary.lastOperationAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.lastOperation(formatDate(summary.lastOperationAt!)),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => showTransactionSheet(
                    context,
                    debtorId: d.id,
                    kind: DebtKind.debt,
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  label: Text(l10n.gaveDebtButton),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showTransactionSheet(
                    context,
                    debtorId: d.id,
                    kind: DebtKind.payment,
                  ),
                  icon: const Icon(Icons.arrow_downward_rounded),
                  label: Text(l10n.receivedPaymentButton),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ],
          ),
          if (_hasInfo(summary)) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    if (d.shopName != null)
                      _InfoRow(icon: Icons.storefront_rounded, text: d.shopName!),
                    for (final phone in summary.phones)
                      _InfoRow(icon: Icons.phone_rounded, text: formatPhone(phone)),
                    if (d.address != null)
                      _InfoRow(icon: Icons.location_on_rounded, text: d.address!),
                    if (d.note != null)
                      _InfoRow(icon: Icons.notes_rounded, text: d.note!),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.operationsTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (details.transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.noOperations,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final t in details.transactions) _TransactionTile(transaction: t),
        ],
      ),
    );
  }

  bool _hasInfo(DebtorSummary summary) {
    final d = summary.debtor;
    return d.shopName != null ||
        d.address != null ||
        d.note != null ||
        summary.phones.isNotEmpty;
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(text)),
        ],
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({required this.transaction});

  final DebtTransaction transaction;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final repo = ref.read(debtorsRepositoryProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteOperationTitle),
        content: Text(l10n.deleteOperationBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.deleteButton)),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      await repo.deleteTransaction(transaction.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDebt = transaction.kind == DebtKind.debt;
    final title = isDebt ? l10n.operationDebt : l10n.operationPayment;
    final color = isDebt ? scheme.error : scheme.primary;
    final sign = isDebt ? '+' : '−';
    final subtitle = [
      formatDate(transaction.occurredAt),
      if (transaction.comment != null) transaction.comment!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(isDebt ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(
              '$sign${formatAmount(transaction.amount)}',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert_rounded),
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: () => _confirmDelete(context, ref),
                  child: Text(l10n.deleteButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
