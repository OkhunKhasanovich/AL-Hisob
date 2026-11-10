import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/debt_kind.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_input_formatter.dart';
import 'debts_providers.dart';

/// Шторка «Дал в долг» / «Получил оплату».
Future<void> showTransactionSheet(
  BuildContext context, {
  required String debtorId,
  required DebtKind kind,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SingleChildScrollView(
        child: TransactionForm(
          debtorId: debtorId,
          kind: kind,
          onDone: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    ),
  );
}

class TransactionForm extends ConsumerStatefulWidget {
  const TransactionForm({
    super.key,
    required this.debtorId,
    required this.kind,
    required this.onDone,
  });

  final String debtorId;
  final DebtKind kind;
  final VoidCallback onDone;

  @override
  ConsumerState<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<TransactionForm> {
  final _amount = TextEditingController();
  final _comment = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  int? get _parsedAmount {
    final v = parseAmount(_amount.text);
    return (v == null || v <= 0) ? null : v;
  }

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Сегодняшняя дата сохраняется с текущим временем, прошлая — с полуднем,
  /// чтобы порядок операций внутри дня оставался предсказуемым.
  DateTime _occurredAt() {
    final now = DateTime.now();
    final sameDay = _date.year == now.year && _date.month == now.month && _date.day == now.day;
    return sameDay ? now : DateTime(_date.year, _date.month, _date.day, 12);
  }

  Future<void> _submit() async {
    final amount = _parsedAmount;
    if (amount == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      await ref.read(debtorsRepositoryProvider).addTransaction(
            debtorId: widget.debtorId,
            kind: widget.kind,
            amount: amount,
            occurredAt: _occurredAt(),
            comment: _comment.text,
          );
      widget.onDone();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.saveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDebt = widget.kind == DebtKind.debt;
    final title = isDebt ? l10n.gaveDebtButton : l10n.receivedPaymentButton;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: const [AmountInputFormatter()],
          style: theme.textTheme.headlineSmall,
          decoration: InputDecoration(
            labelText: l10n.amountLabel,
            suffixText: l10n.currencySum,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_rounded),
          label: Text('${l10n.dateLabel}: ${formatDate(_date)}'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _comment,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.commentLabel,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: (_parsedAmount == null || _saving) ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Text(title),
        ),
      ],
    );
  }
}
