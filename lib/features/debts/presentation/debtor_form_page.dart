import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/amount_input_formatter.dart';
import '../data/debtors_repository.dart';
import 'debts_providers.dart';

/// Создание ([debtorId] == null) и редактирование должника.
class DebtorFormPage extends ConsumerStatefulWidget {
  const DebtorFormPage({super.key, this.debtorId});

  final String? debtorId;

  @override
  ConsumerState<DebtorFormPage> createState() => _DebtorFormPageState();
}

class _DebtorFormPageState extends ConsumerState<DebtorFormPage> {
  Future<DebtorDetails?>? _loading;

  @override
  void initState() {
    super.initState();
    final id = widget.debtorId;
    if (id != null) {
      _loading = ref.read(debtorsRepositoryProvider).loadDetails(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.debtorId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l10n.debtorEditTitle : l10n.debtorNewTitle),
      ),
      body: isEdit
          ? FutureBuilder<DebtorDetails?>(
              future: _loading,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final details = snapshot.data;
                if (details == null) return const SizedBox.shrink();
                return _DebtorFormBody(
                  debtorId: widget.debtorId,
                  initial: details,
                );
              },
            )
          : const _DebtorFormBody(),
    );
  }
}

class _DebtorFormBody extends ConsumerStatefulWidget {
  const _DebtorFormBody({this.debtorId, this.initial});

  final String? debtorId;
  final DebtorDetails? initial;

  @override
  ConsumerState<_DebtorFormBody> createState() => _DebtorFormBodyState();
}

class _DebtorFormBodyState extends ConsumerState<_DebtorFormBody> {
  static const _maxPhones = 5;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _shop;
  late final TextEditingController _address;
  late final TextEditingController _note;
  final _currentDebt = TextEditingController();
  late final List<TextEditingController> _phones;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial?.summary.debtor;
    _name = TextEditingController(text: d?.name ?? '');
    _shop = TextEditingController(text: d?.shopName ?? '');
    _address = TextEditingController(text: d?.address ?? '');
    _note = TextEditingController(text: d?.note ?? '');
    final phones = widget.initial?.summary.phones ?? const <String>[];
    _phones = [
      for (final p in phones)
        TextEditingController(text: formatPhone(p).replaceFirst('+998 ', '')),
      if (phones.isEmpty) TextEditingController(),
    ];
  }

  @override
  void dispose() {
    for (final c in [_name, _shop, _address, _note, _currentDebt, ..._phones]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final repo = ref.read(debtorsRepositoryProvider);
    final input = DebtorInput(
      name: _name.text,
      shopName: _shop.text,
      address: _address.text,
      note: _note.text,
      phones: [for (final c in _phones) c.text],
      // Текущий долг задаётся только у нового должника; дальше — через операции.
      initialDebt: widget.debtorId == null ? (parseAmount(_currentDebt.text) ?? 0) : 0,
      initialDebtComment: context.l10n.initialDebtComment,
    );
    try {
      final id = widget.debtorId;
      if (id == null) {
        final newId = await repo.createDebtor(input);
        if (mounted) context.pushReplacement(Routes.debtorDetails(newId));
      } else {
        await repo.updateDebtor(id, input);
        if (mounted) context.pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.saveError)));
    }
  }

  InputDecoration _decoration(String label, {IconData? icon, String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Form(
      key: _formKey,
      // Не ListView: он убирает поля за экраном, и validate() их бы не проверял.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 120,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.debtorNameError : null,
              decoration: _decoration(
                l10n.debtorNameLabel,
                icon: Icons.person_rounded,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _shop,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                l10n.debtorShopLabel,
                icon: Icons.storefront_rounded,
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _phones.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phones[i],
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty || isValidPhone(v))
                          ? null
                          : l10n.debtorPhoneError,
                      decoration: _decoration(
                        l10n.debtorPhoneLabel,
                        icon: Icons.phone_rounded,
                        hint: l10n.debtorPhoneHint,
                      ).copyWith(prefixText: '+998 '),
                    ),
                  ),
                  if (_phones.length > 1)
                    IconButton(
                      tooltip: l10n.removePhone,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: () =>
                          setState(() => _phones.removeAt(i).dispose()),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (_phones.length < _maxPhones)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _phones.add(TextEditingController())),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.addPhone),
                ),
              ),
            const SizedBox(height: 8),
            // Новый должник: сразу указываем, сколько он должен сейчас (из тетради).
            if (widget.debtorId == null) ...[
              TextFormField(
                key: const ValueKey('current-debt'),
                controller: _currentDebt,
                keyboardType: TextInputType.number,
                inputFormatters: const [AmountInputFormatter()],
                textInputAction: TextInputAction.next,
                decoration: _decoration(
                  l10n.debtorCurrentDebtLabel,
                  icon: Icons.payments_rounded,
                ).copyWith(suffixText: l10n.currencySum, helperText: l10n.debtorCurrentDebtHint),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _address,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                l10n.debtorAddressLabel,
                icon: Icons.location_on_rounded,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: _decoration(
                l10n.debtorNoteLabel,
                icon: Icons.notes_rounded,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(l10n.saveButton),
            ),
          ],
        ),
      ),
    );
  }
}
