import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/domain/shop_role.dart';
import '../../core/l10n/l10n.dart';
import 'role_option_card.dart';
import 'shop_name_validator.dart';
import 'shop_role_l10n.dart';

/// Форма «название + роль». Используется в онбординге и при редактировании.
class ShopProfileForm extends StatefulWidget {
  const ShopProfileForm({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.initialName = '',
    this.initialRole,
  });

  final String submitLabel;
  final String initialName;
  final ShopRole? initialRole;

  /// Бросьте исключение, если сохранить не удалось: форма покажет ошибку.
  final Future<void> Function(String name, ShopRole role) onSubmit;

  @override
  State<ShopProfileForm> createState() => _ShopProfileFormState();
}

class _ShopProfileFormState extends State<ShopProfileForm> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName)
    ..addListener(() => setState(() {}));
  late ShopRole? _role = widget.initialRole;
  bool _saving = false;

  bool get _canSubmit => !_saving && _role != null && isValidShopName(_name.text);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.onSubmit(_name.text, _role!);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.saveError)));
    }
    // При успехе экран закрывается/заменяется вызывающим кодом.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _name,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          maxLength: shopNameMaxLength,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) => isValidShopName(v ?? '') ? null : l10n.shopNameError,
          decoration: InputDecoration(
            labelText: l10n.shopNameLabel,
            hintText: l10n.shopNameHint,
            prefixIcon: const Icon(Icons.store_mall_directory_rounded),
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.roleLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final role in onboardingRoles) ...[
          RoleOptionCard(
            role: role,
            selected: _role == role,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _role = role);
            },
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
