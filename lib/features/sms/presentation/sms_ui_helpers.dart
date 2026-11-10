import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../data/sms_providers.dart';
import '../domain/sms_sender.dart';
export '../../profile/shop_name.dart';

/// Понятная причина ошибки отправки на языке приложения.
String smsReasonText(AppLocalizations l10n, String? error) => switch (error) {
      'no_permission' => l10n.smsReasonNoPermission,
      'no_service' => l10n.smsReasonNoService,
      'radio_off' => l10n.smsReasonRadioOff,
      'timeout' => l10n.smsReasonTimeout,
      _ => l10n.smsReasonOther,
    };

/// Проверяет и при необходимости запрашивает разрешения на отправку SMS.
/// Возвращает `true`, если отправлять можно.
Future<bool> ensureSmsPermission(BuildContext context, WidgetRef ref) async {
  final sender = ref.read(smsSenderProvider);
  var state = await sender.permissions();
  if (state.canSend && (state.canListSims || !sender.supportsSimSelection)) return true;

  if (!context.mounted) return false;
  final l10n = context.l10n;

  if (!state.canSend) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.sms_rounded),
        title: Text(l10n.smsPermissionTitle),
        content: Text(l10n.smsPermissionBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.continueButton)),
        ],
      ),
    );
    if (proceed != true) return false;
  }

  state = await sender.requestPermissions();
  ref.invalidate(simsProvider);
  if (state.canSend) return true;
  if (!context.mounted) return false;

  if (state.blockedForever) await _offerSettings(context, sender);
  return false;
}

Future<void> _offerSettings(BuildContext context, SmsSender sender) async {
  final l10n = context.l10n;
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.settings_rounded),
      title: Text(l10n.smsPermissionTitle),
      content: Text(l10n.smsPermissionSettingsBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.openSettingsButton)),
      ],
    ),
  );
  if (open == true) await sender.openAppSettings();
}

/// Выбор SIM: если SIM одна или выбор не поддерживается — `null` (по умолчанию).
class SimChoice extends StatelessWidget {
  const SimChoice({
    super.key,
    required this.sims,
    required this.selected,
    required this.onSelected,
  });

  final List<SimInfo> sims;
  final int? selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (sims.length < 2) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.smsSimLabel, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sim in sims)
              ChoiceChip(
                label: Text(sim.label),
                selected: selected == sim.subscriptionId,
                onSelected: (_) => onSelected(sim.subscriptionId),
              ),
          ],
        ),
      ],
    );
  }
}

/// Выбранная SIM по умолчанию: SIM для SMS по умолчанию, иначе первая.
int? defaultSimId(List<SimInfo> sims) {
  if (sims.isEmpty) return null;
  return sims.firstWhere((s) => s.isDefaultForSms, orElse: () => sims.first).subscriptionId;
}

/// Подпись языка шаблона.
String languageLabel(String code) => languageNames[code] ?? code;
