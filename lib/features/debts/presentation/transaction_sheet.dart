import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/debt_kind.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_input_formatter.dart';
import '../data/debtors_repository.dart' show PaymentExceedsDebtException;
import 'debts_providers.dart';

/// Шторка «Дал в долг» / «Получил оплату».
Future<void> showTransactionSheet(
  BuildContext context, {
  required String debtorId,
  required DebtKind kind,
}) {
  return showModalBottomSheet<void>(
    // Поверх панели вкладок, а не под ней: панель не просвечивает и не перекрывает кнопки шторки.
    useRootNavigator: true,
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

  /// Подставляет сумму в поле (с пробелами между тысячами) и ставит курсор в конец.
  void _fill(int amount) {
    HapticFeedback.selectionClick();
    final text = formatAmount(amount);
    _amount.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
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
    } on PaymentExceedsDebtException catch (e) {
      // Долг успел уменьшиться (например, пришла синхронизация): подсказываем актуальный предел.
      if (!mounted) return;
      setState(() => _saving = false);
      final l10n = context.l10n;
      if (e.balance > 0 && amount > e.balance) _fill(e.balance);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.payExceedsDebt('${formatAmount(e.balance)} ${l10n.currencySum}'))),
        );
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
    final loadedBalance = ref.watch(debtorDetailsProvider(widget.debtorId)).value?.summary.balance;
    final balance = loadedBalance ?? 0;
    // Оплату нельзя ввести больше текущего долга; у выдачи долга предела нет.
    final limit = (!isDebt && loadedBalance != null) ? (balance > 0 ? balance : 0) : null;
    final noDebt = limit == 0;
    final overLimit = limit != null && (_parsedAmount ?? 0) > limit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: true,
          enabled: !noDebt,
          keyboardType: TextInputType.number,
          inputFormatters: [AmountInputFormatter(max: limit)],
          style: theme.textTheme.headlineSmall,
          decoration: InputDecoration(
            labelText: l10n.amountLabel,
            suffixText: l10n.currencySum,
            helperText: noDebt
                ? l10n.payNoDebt
                : (limit != null ? l10n.payAmountMax('${formatAmount(limit)} ${l10n.currencySum}') : null),
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
        ),
        if (!isDebt && balance > 0) ...[
          const SizedBox(height: 10),
          _FullDebtSuggestion(
            label: l10n.payFullDebtLabel('${formatAmount(balance)} ${l10n.currencySum}'),
            hint: l10n.payFullDebtHint,
            selected: _parsedAmount == balance,
            onTap: () => _fill(balance),
          ),
        ],
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
          onPressed: (_parsedAmount == null || _saving || noDebt || overLimit) ? null : _submit,
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

/// Подсказка под полем суммы при погашении: весь долг одним нажатием.
class _FullDebtSuggestion extends StatelessWidget {
  const _FullDebtSuggestion({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const ValueKey('full-debt-suggestion'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.bolt_rounded,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleSmall),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
