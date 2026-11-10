import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../domain/debt_filter.dart';

/// Верхняя карточка экрана «Долги»: сколько вам должны всего, сколько должников
/// и сколько из них просрочено.
class DebtsOverviewCard extends StatelessWidget {
  const DebtsOverviewCard({super.key, required this.overview});

  final DebtsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.secondaryContainer],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.debtsTotalLabel,
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 2),
              TweenAnimationBuilder<double>(
                tween: Tween(end: overview.totalOwed.toDouble()),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${formatAmount(value.round())} ${l10n.currencySum}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Pill(
                    icon: Icons.groups_rounded,
                    text: l10n.debtsCountLabel(overview.debtorCount),
                    background: scheme.surface.withValues(alpha: 0.55),
                    foreground: scheme.onSurface,
                  ),
                  if (overview.overdueCount > 0)
                    _Pill(
                      icon: Icons.schedule_rounded,
                      text: l10n.debtsOverdueLabel(overview.overdueCount),
                      background: scheme.errorContainer,
                      foreground: scheme.onErrorContainer,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 5),
            Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
