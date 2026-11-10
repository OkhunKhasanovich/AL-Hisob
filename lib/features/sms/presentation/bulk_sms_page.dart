import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../debts/domain/debt_filter.dart';
import '../../debts/domain/debt_summary.dart';
import '../../debts/presentation/debts_providers.dart';
import '../data/sms_providers.dart';
import '../domain/bulk_sms_runner.dart';
import '../domain/reminder_text.dart';
import '../domain/sms_sender.dart';
import '../domain/sms_template.dart';
import '../domain/sms_text.dart';
import 'sms_ui_helpers.dart';

enum _Phase { choosing, sending, finished }

class BulkSmsPage extends ConsumerStatefulWidget {
  const BulkSmsPage({super.key});

  @override
  ConsumerState<BulkSmsPage> createState() => _BulkSmsPageState();
}

class _BulkSmsPageState extends ConsumerState<BulkSmsPage> {
  final Set<String> _selected = {};
  bool _selectionInitialized = false;
  String? _language;
  late DateTime _dueDate = defaultDueDate(DateTime.now());
  int? _simId;

  _Phase _phase = _Phase.choosing;
  BulkSmsRunner? _runner;
  BulkSmsProgress? _progress;
  StreamSubscription<BulkSmsProgress>? _subscription;

  @override
  void dispose() {
    _runner?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  String _currentLanguage(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return _language ?? (smsLanguages.contains(code) ? code : 'uz');
  }

  /// Получатели: есть долг и телефон. Крупные долги — выше.
  List<DebtorSummary> _candidates(List<DebtorSummary> all) =>
      all.where((s) => s.balance > 0 && s.phones.isNotEmpty).toList()
        ..sort((a, b) => b.balance.compareTo(a.balance));

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

  List<BulkSmsItem> _buildItems(List<DebtorSummary> candidates, String language) {
    final template = ref.read(smsTemplatesProvider).value?[language] ?? defaultSmsTemplates[language]!;
    final shop = readShopName(ref, context);
    return [
      for (final s in candidates)
        if (_selected.contains(s.debtor.id))
          BulkSmsItem(
            debtorId: s.debtor.id,
            debtorName: s.debtor.name,
            phone: s.phones.first,
            body: buildReminderText(
              template: template,
              language: language,
              debtorName: s.debtor.name,
              amount: s.balance,
              shopName: shop,
              dueDate: _dueDate,
            ),
          ),
    ];
  }

  Future<void> _start(List<DebtorSummary> candidates, String language) async {
    final l10n = context.l10n;
    final items = _buildItems(candidates, language);
    if (items.isEmpty) return;

    final seconds = ref.read(smsPauseSecondsProvider);
    final parts = items.fold<int>(0, (sum, i) => sum + smsLength(i.body).segments);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bulkConfirmTitle(items.length)),
        content: Text(l10n.bulkConfirmBody(parts, seconds)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.smsSendButton)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await ensureSmsPermission(context, ref)) return;
    if (!mounted) return;

    final service = ref.read(smsServiceProvider);
    final simId = _simId ?? defaultSimId(ref.read(simsProvider).value ?? const []);
    final runner = BulkSmsRunner(
      pause: Duration(seconds: seconds),
      send: (item) => service.sendItem(item, subscriptionId: simId),
    );
    HapticFeedback.mediumImpact();
    setState(() {
      _runner = runner;
      _phase = _Phase.sending;
      _progress = null;
    });
    _subscription = runner.run(items).listen((p) {
      if (!mounted) return;
      setState(() {
        _progress = p;
        if (p.finished) _phase = _Phase.finished;
      });
      if (p.finished) HapticFeedback.heavyImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sender = ref.watch(smsSenderProvider);
    final all = ref.watch(debtorSummariesProvider).value ?? const <DebtorSummary>[];
    final candidates = _candidates(all);
    final config = ref.watch(debtFilterConfigProvider);
    final language = _currentLanguage(context);
    watchShopName(ref, context); // подписка на профиль: название магазина для текста SMS

    if (!_selectionInitialized && all.isNotEmpty) {
      _selectionInitialized = true;
      final now = DateTime.now();
      _selected.addAll(
        candidates.where((s) => isOverdue(s, now, config)).map((s) => s.debtor.id),
      );
    }

    return PopScope(
      canPop: _phase != _Phase.sending,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.bulkSmsTitle)),
        body: switch (_phase) {
          _Phase.choosing => _buildChoosing(context, sender, candidates, config, language),
          _ => _buildProgress(context),
        },
      ),
    );
  }

  Widget _buildChoosing(
    BuildContext context,
    SmsSender sender,
    List<DebtorSummary> candidates,
    DebtFilterConfig config,
    String language,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sims = ref.watch(simsProvider).value ?? const <SimInfo>[];
    final seconds = ref.watch(smsPauseSecondsProvider);
    final now = DateTime.now();
    final selectedCount = candidates.where((s) => _selected.contains(s.debtor.id)).length;

    if (!sender.silent) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n.bulkComposerUnsupported, textAlign: TextAlign.center),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Text(l10n.smsLanguageLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final code in smsLanguages)
                  ChoiceChip(
                    label: Text(languageLabel(code)),
                    selected: language == code,
                    onSelected: (_) => setState(() => _language = code),
                  ),
              ]),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded),
                label: Text('${l10n.smsDueDateLabel}: ${formatDate(_dueDate)}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 16),
              Text(l10n.bulkPauseLabel(seconds), style: theme.textTheme.titleSmall),
              Slider(
                value: seconds.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$seconds',
                onChanged: (v) => ref.read(smsPauseSecondsProvider.notifier).set(v.round()),
              ),
              if (sims.length > 1) ...[
                SimChoice(
                  sims: sims,
                  selected: _simId ?? defaultSimId(sims),
                  onSelected: (id) => setState(() => _simId = id),
                ),
                const SizedBox(height: 16),
              ],
              if (candidates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(l10n.bulkNoRecipients, textAlign: TextAlign.center),
                )
              else ...[
                Wrap(spacing: 8, children: [
                  ActionChip(
                    label: Text(l10n.bulkSelectAll),
                    onPressed: () => setState(
                        () => _selected..clear()..addAll(candidates.map((s) => s.debtor.id))),
                  ),
                  ActionChip(
                    label: Text(l10n.bulkSelectOverdue),
                    onPressed: () => setState(() => _selected
                      ..clear()
                      ..addAll(candidates
                          .where((s) => isOverdue(s, now, config))
                          .map((s) => s.debtor.id))),
                  ),
                  ActionChip(
                    label: Text(l10n.bulkSelectNone),
                    onPressed: () => setState(_selected.clear),
                  ),
                ]),
                const SizedBox(height: 8),
                for (final s in candidates)
                  CheckboxListTile(
                    key: ValueKey(s.debtor.id),
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(s.debtor.id),
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _selected.add(s.debtor.id);
                      } else {
                        _selected.remove(s.debtor.id);
                      }
                    }),
                    title: Text(s.debtor.name),
                    subtitle: Text(
                      '${formatPhone(s.phones.first)}'
                      '${isOverdue(s, now, config) ? ' · ${l10n.overdueBadge}' : ''}',
                    ),
                    secondary: Text(
                      '${formatAmount(s.balance)} ${l10n.currencySum}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: selectedCount == 0 ? null : () => _start(candidates, language),
              icon: const Icon(Icons.send_rounded),
              label: Text(l10n.bulkSendButton(selectedCount)),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final p = _progress;
    final finished = _phase == _Phase.finished;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              finished
                  ? (p?.cancelled ?? false ? Icons.stop_circle_rounded : Icons.check_circle_rounded)
                  : Icons.sms_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              finished
                  ? (p?.cancelled ?? false ? l10n.bulkStopped : l10n.bulkFinished)
                  : l10n.bulkSending,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(value: p?.fraction ?? 0, minHeight: 8),
            const SizedBox(height: 12),
            if (p != null) ...[
              Text(l10n.bulkProgress(p.processed, p.total), style: theme.textTheme.titleMedium),
              if (!finished && p.current != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(p.current!.debtorName, style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: 12),
              Text(l10n.bulkSentCount(p.sent)),
              if (p.failed > 0)
                Text(l10n.bulkFailedCount(p.failed),
                    style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            if (finished)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.bulkDone),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _runner?.cancel(),
                icon: const Icon(Icons.stop_rounded),
                label: Text(l10n.bulkStop),
              ),
          ],
        ),
      ),
    );
  }
}
