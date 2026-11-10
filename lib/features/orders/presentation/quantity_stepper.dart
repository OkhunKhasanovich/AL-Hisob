import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n.dart';

/// Количество с кнопками «−» / «+» и вводом числа по нажатию.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.max = 9999999,
  });

  final int quantity;
  final ValueChanged<int> onChanged;
  final int max;

  Future<void> _edit(BuildContext context) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _QuantityDialog(initial: quantity),
    );
    if (value != null && value >= 1) onChanged(value.clamp(1, max));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_rounded),
          onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
        ),
        InkWell(
          onTap: () => _edit(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('$quantity', style: theme.textTheme.titleMedium),
          ),
        ),
        IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_rounded),
          onPressed: quantity < max ? () => onChanged(quantity + 1) : null,
        ),
      ],
    );
  }
}

/// Ввод количества числом. Контроллер живёт внутри диалога (см. `_ReasonDialog`).
class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.initial});

  final int initial;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final TextEditingController _controller = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: () => Navigator.pop(context, int.tryParse(_controller.text)),
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }
}
