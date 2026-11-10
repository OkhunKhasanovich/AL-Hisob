import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_input_formatter.dart';

/// Блок настроек «Книга должников» на вкладке «Ещё».
class DebtSettingsSection extends ConsumerWidget {
  const DebtSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final config = ref.watch(debtFilterConfigProvider);
    final controller = ref.read(debtFilterConfigProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.debtBookSection, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_rounded),
          title: Text(l10n.overdueDaysSetting),
          trailing: Text('${config.overdueDays}', style: Theme.of(context).textTheme.titleMedium),
          onTap: () async {
            final value = await _askNumber(context, l10n.overdueDaysSetting, config.overdueDays,
                grouped: false);
            if (value != null) controller.update(overdueDays: value);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.trending_up_rounded),
          title: Text(l10n.largeDebtSetting),
          trailing: Text(
            '${formatAmount(config.largeDebtThreshold)} ${l10n.currencySum}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          onTap: () async {
            final value = await _askNumber(
                context, l10n.largeDebtSetting, config.largeDebtThreshold,
                grouped: true);
            if (value != null) controller.update(largeDebtThreshold: value);
          },
        ),
      ],
    );
  }
}

Future<int?> _askNumber(
  BuildContext context,
  String title,
  int initial, {
  required bool grouped,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final l10n = ctx.l10n;
      final controller = TextEditingController(
        text: grouped ? formatAmount(initial) : '$initial',
      );
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              if (grouped)
                const AmountInputFormatter()
              else
                FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancelButton)),
            FilledButton(
              onPressed: () {
                final v = parseAmount(controller.text);
                if (v == null || v <= 0) {
                  setState(() => error = l10n.settingValueError);
                } else {
                  Navigator.pop(ctx, v);
                }
              },
              child: Text(l10n.saveButton),
            ),
          ],
        ),
      );
    },
  );
}
