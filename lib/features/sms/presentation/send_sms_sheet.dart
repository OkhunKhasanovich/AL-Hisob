import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/sms_status.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../debts/domain/debt_summary.dart';
import '../data/sms_providers.dart';
import '../domain/reminder_text.dart';
import '../domain/sms_sender.dart';
import '../domain/sms_template.dart';
import '../domain/sms_text.dart';
import 'sms_ui_helpers.dart';

/// Шторка отправки SMS-напоминания одному должнику.
Future<void> showSendSmsSheet(BuildContext context, DebtorSummary debtor) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) => SendSmsForm(debtor: debtor, scrollController: controller),
    ),
  );
}

class SendSmsForm extends ConsumerStatefulWidget {
  const SendSmsForm({super.key, required this.debtor, this.scrollController});

  final DebtorSummary debtor;
  final ScrollController? scrollController;

  @override
  ConsumerState<SendSmsForm> createState() => _SendSmsFormState();
}

class _SendSmsFormState extends ConsumerState<SendSmsForm> {
  late String _phone = widget.debtor.phones.first;
  String? _language;
  late DateTime _dueDate = defaultDueDate(DateTime.now());
  int? _simId;
  bool _sending = false;

  String _currentLanguage(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return _language ?? (smsLanguages.contains(code) ? code : 'uz');
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _send(String text) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    HapticFeedback.mediumImpact();

    if (!await ensureSmsPermission(context, ref)) return;
    if (!mounted) return;

    setState(() => _sending = true);
    final result = await ref.read(smsServiceProvider).send(
          debtorId: widget.debtor.debtor.id,
          phone: _phone,
          body: text,
          subscriptionId: _simId ?? defaultSimId(ref.read(simsProvider).value ?? const []),
        );
    if (!mounted) return;

    if (result.isFailure) {
      setState(() => _sending = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(l10n.smsFailed(smsReasonText(l10n, result.error))),
        ));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(result.status == SmsStatus.composerOpened
            ? l10n.smsComposerOpened
            : l10n.smsSentOk),
      ));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sender = ref.watch(smsSenderProvider);
    final sims = ref.watch(simsProvider).value ?? const <SimInfo>[];
    final templates = ref.watch(smsTemplatesProvider).value;
    final language = _currentLanguage(context);
    final summary = widget.debtor;

    final template = templates?[language] ?? defaultSmsTemplates[language]!;
    final text = buildReminderText(
      template: template,
      language: language,
      debtorName: summary.debtor.name,
      amount: summary.balance > 0 ? summary.balance : 0,
      shopName: watchShopName(ref, context),
      dueDate: _dueDate,
    );
    final length = smsLength(text);

    final content = ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      children: [
        Text(l10n.smsReminderTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${summary.debtor.name} · ${formatAmount(summary.balance)} ${l10n.currencySum}',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (summary.phones.length > 1) ...[
          const SizedBox(height: 16),
          Text(l10n.debtorPhoneLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in summary.phones)
                ChoiceChip(
                  label: Text(formatPhone(p)),
                  selected: _phone == p,
                  onSelected: (_) => setState(() => _phone = p),
                ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.phone_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(formatPhone(_phone)),
          ]),
        ],
        const SizedBox(height: 16),
        Text(l10n.smsLanguageLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final code in smsLanguages)
              ChoiceChip(
                label: Text(languageLabel(code)),
                selected: language == code,
                onSelected: (_) => setState(() => _language = code),
              ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.event_rounded),
          label: Text('${l10n.smsDueDateLabel}: ${formatDate(_dueDate)}'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (sender.supportsSimSelection && sims.length > 1) ...[
          const SizedBox(height: 16),
          SimChoice(
            sims: sims,
            selected: _simId ?? defaultSimId(sims),
            onSelected: (id) => setState(() => _simId = id),
          ),
        ],
        const SizedBox(height: 16),
        Text(l10n.smsPreviewLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(text),
                const SizedBox(height: 8),
                Text(
                  l10n.smsLengthInfo(length.characters, length.segments),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    // Кнопка закреплена внизу: её не нужно искать прокруткой.
    return Column(
      children: [
        Expanded(child: content),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: FilledButton.icon(
              onPressed: _sending ? null : () => _send(text),
              icon: _sending
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.send_rounded),
              label: Text(sender.silent ? l10n.smsSendButton : l10n.smsOpenComposerButton),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ),
        ),
      ],
    );
  }
}
