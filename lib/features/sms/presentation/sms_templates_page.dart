import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../data/sms_providers.dart';
import '../domain/reminder_text.dart';
import '../domain/sms_template.dart';
import '../domain/sms_text.dart';
import 'sms_ui_helpers.dart';

/// Список шаблонов (по одному на язык) с редактированием.
class SmsTemplatesPage extends ConsumerWidget {
  const SmsTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final templates = ref.watch(smsTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.smsTemplatesTitle)),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (map) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final code in smsLanguages)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    await showModalBottomSheet<void>(
                      // Поверх стеклянной панели вкладок, а не под ней.
                      useRootNavigator: true,
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.9,
                        maxChildSize: 0.95,
                        builder: (context, controller) => _TemplateEditor(
                          language: code,
                          initial: map[code]!,
                          scrollController: controller,
                        ),
                      ),
                    );
                    ref.invalidate(smsTemplatesProvider);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(languageLabel(code), style: theme.textTheme.titleMedium),
                          const Spacer(),
                          if (map[code] != defaultSmsTemplates[code])
                            Chip(
                              label: Text(l10n.smsTemplateEdited),
                              visualDensity: VisualDensity.compact,
                            ),
                          const Icon(Icons.edit_rounded, size: 20),
                        ]),
                        const SizedBox(height: 8),
                        Text(map[code]!, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TemplateEditor extends ConsumerStatefulWidget {
  const _TemplateEditor({
    required this.language,
    required this.initial,
    required this.scrollController,
  });

  final String language;
  final String initial;
  final ScrollController scrollController;

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _insert(String tag) {
    HapticFeedback.selectionClick();
    final value = _controller.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    final text = value.text.replaceRange(start, end, tag);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + tag.length),
    );
  }

  Future<void> _save() async {
    final repo = ref.read(smsTemplatesRepositoryProvider);
    await repo.save(widget.language, _controller.text);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await ref.read(smsTemplatesRepositoryProvider).resetToDefault(widget.language);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final text = _controller.text;
    final unknown = unknownPlaceholders(text);
    final preview = buildReminderText(
      template: text,
      language: widget.language,
      debtorName: 'Alisher',
      amount: 1500000,
      shopName: watchShopName(ref, context),
      dueDate: defaultDueDate(DateTime.now()),
    );
    final length = smsLength(preview);
    final isEmpty = text.trim().isEmpty;

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      children: [
        Text(languageLabel(widget.language), style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
            errorText: isEmpty ? l10n.smsTemplateEmpty : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(l10n.smsTemplateVariables, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in SmsVariable.values)
            ActionChip(
              label: Text(variableTag(widget.language, v)),
              onPressed: () => _insert(variableTag(widget.language, v)),
            ),
        ]),
        if (unknown.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            l10n.smsTemplateUnknown(unknown.join(', ')),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Text(l10n.smsTemplatePreview, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preview),
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
        const SizedBox(height: 16),
        FilledButton(
          onPressed: isEmpty ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(l10n.saveButton),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _reset, child: Text(l10n.smsTemplateReset)),
      ],
    );
  }
}
