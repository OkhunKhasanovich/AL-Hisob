import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import 'debts_providers.dart';

/// Количество тестовых должников, которое добавляет кнопка.
const demoDebtorCount = 50;

/// Блок «Тестовые данные» на вкладке «Ещё»: наполняет книгу выдуманными должниками
/// и убирает их одним нажатием.
class DemoDataSection extends ConsumerStatefulWidget {
  const DemoDataSection({super.key});

  @override
  ConsumerState<DemoDataSection> createState() => _DemoDataSectionState();
}

class _DemoDataSectionState extends ConsumerState<DemoDataSection> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => _run(() async {
    final l10n = context.l10n;
    final added = await ref.read(debtorsRepositoryProvider).seedDemoDebtors(count: demoDebtorCount);
    return l10n.demoDataAdded(added);
  });

  Future<void> _remove() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.demoDataRemoveTitle),
        content: Text(l10n.demoDataRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final removed = await ref.read(debtorsRepositoryProvider).deleteDemoDebtors();
      return l10n.demoDataRemoved(removed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.demoDataSection, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.science_rounded),
          title: Text(l10n.demoDataAdd(demoDebtorCount)),
          subtitle: Text(l10n.demoDataAddHint),
          enabled: !_busy,
          onTap: _add,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_sweep_rounded),
          title: Text(l10n.demoDataRemove),
          enabled: !_busy,
          onTap: _remove,
        ),
      ],
    );
  }
}
