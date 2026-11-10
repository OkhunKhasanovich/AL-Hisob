import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../debts/data/debtors_repository.dart';
import '../../debts/domain/debt_summary.dart';
import '../../debts/domain/search/debtor_search.dart';
import '../../debts/presentation/debts_providers.dart';

/// Выбранный покупатель.
typedef PickedCustomer = ({String id, String name});

/// Шторка выбора покупателя из книги должников; можно сразу завести нового.
Future<PickedCustomer?> showCustomerPicker(BuildContext context) {
  return showModalBottomSheet<PickedCustomer>(
    // Поверх стеклянной панели вкладок, а не под ней.
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => _CustomerPicker(scrollController: controller),
    ),
  );
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _query = '';

  Future<void> _createCustomer() async {
    final created = await showDialog<PickedCustomer>(
      context: context,
      builder: (_) => const _NewCustomerDialog(),
    );
    if (created != null && mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final all = ref.watch(debtorSummariesProvider).value ?? const <DebtorSummary>[];
    final hits = DebtorSearchIndex(all).search(_query);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
        ),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
          title: Text(l10n.orderNewCustomer),
          onTap: _createCustomer,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: hits.length,
            itemBuilder: (context, i) {
              final s = hits[i].summary;
              return ListTile(
                leading: CircleAvatar(
                  child: Text(s.debtor.name.isEmpty ? '?' : s.debtor.name.characters.first.toUpperCase()),
                ),
                title: Text(s.debtor.name),
                subtitle: Text([
                  if (s.debtor.shopName != null) s.debtor.shopName!,
                  if (s.phones.isNotEmpty) formatPhone(s.phones.first),
                ].join(' · ')),
                trailing: s.balance > 0
                    ? Text(
                        '${formatAmount(s.balance)} ${l10n.currencySum}',
                        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error),
                      )
                    : null,
                onTap: () => Navigator.of(context).pop((id: s.debtor.id, name: s.debtor.name)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NewCustomerDialog extends ConsumerStatefulWidget {
  const _NewCustomerDialog();

  @override
  ConsumerState<_NewCustomerDialog> createState() => _NewCustomerDialogState();
}

class _NewCustomerDialogState extends ConsumerState<_NewCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(debtorsRepositoryProvider);
      final id = await repo.createDebtor(DebtorInput(
        name: _name.text,
        phones: [if (_phone.text.trim().isNotEmpty) _phone.text],
      ));
      if (mounted) Navigator.of(context).pop((id: id, name: _name.text.trim()));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.saveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.orderNewCustomer),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? l10n.debtorNameError : null,
              decoration: InputDecoration(labelText: l10n.debtorNameLabel),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  (v == null || v.trim().isEmpty || isValidPhone(v)) ? null : l10n.debtorPhoneError,
              decoration: InputDecoration(
                labelText: l10n.debtorPhoneLabel,
                prefixText: '+998 ',
                hintText: l10n.debtorPhoneHint,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
        FilledButton(onPressed: _saving ? null : _save, child: Text(l10n.saveButton)),
      ],
    );
  }
}
