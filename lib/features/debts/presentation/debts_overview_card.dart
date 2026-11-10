import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_trend.dart';
import 'debt_trend_backdrop.dart';

/// Высота нижней полосы: слева сводка, справа график.
const _bandHeight = 68.0;
const _cardPadding = EdgeInsets.fromLTRB(20, 16, 20, 16);

/// Верхняя карточка экрана «Долги»: сколько вам должны всего, динамика за неделю,
/// сколько должников и сколько из них просрочено.
///
/// Раскладка не даёт элементам накладываться: сверху подпись и сумма, внизу слева —
/// сводка, справа (с 40% ширины) — линия динамики.
class DebtsOverviewCard extends StatelessWidget {
  const DebtsOverviewCard({super.key, required this.overview, this.trend});

  final DebtsOverview overview;

  /// Динамика общего долга; `null` — график не рисуется.
  final DebtTrend? trend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(28);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.secondaryContainer],
          ),
          border: Border.all(color: scheme.onPrimaryContainer.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              // Мягкий блик в левом верхнем углу — карточка не выглядит плоской.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.9, -1.1),
                      radius: 1.1,
                      colors: [
                        scheme.onPrimaryContainer.withValues(alpha: 0.10),
                        scheme.onPrimaryContainer.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              if (trend != null)
                Positioned.fill(
                  child: DebtTrendBackdrop(
                    trend: trend!,
                    bandHeight: _bandHeight,
                    bottomInset: _cardPadding.bottom,
                  ),
                ),
              _Content(overview: overview, hasChart: trend != null),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.overview, required this.hasChart});

  final DebtsOverview overview;
  final bool hasChart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final stats = [
      _Stat(
        icon: Icons.groups_rounded,
        text: l10n.debtsCountLabel(overview.debtorCount),
        color: scheme.onPrimaryContainer,
      ),
      if (overview.overdueCount > 0)
        _Stat(
          icon: Icons.schedule_rounded,
          text: l10n.debtsOverdueLabel(overview.overdueCount),
          color: scheme.error,
          emphasize: true,
        ),
    ];

    return Padding(
      padding: _cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 20,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.debtsTotalLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            tween: Tween(end: overview.totalOwed.toDouble()),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  text: formatAmount(value.round()),
                  children: [
                    // Валюта на конце суммы — полупрозрачная, чтобы число читалось первым.
                    TextSpan(
                      text: ' ${l10n.currencySum}',
                      style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (hasChart)
            // Слева — сводка столбиком, правее 40% ширины карточки начинается график.
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth + _cardPadding.horizontal;
                // Начало линии (40%) почти прозрачное, поэтому сводке можно чуть заходить правее.
                final statsWidth = cardWidth * 0.46 - _cardPadding.left;
                return SizedBox(
                  height: _bandHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: statsWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < stats.length; i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            stats[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            )
          else
            Wrap(spacing: 16, runSpacing: 6, children: stats),
        ],
      ),
    );
  }
}

/// Строка сводки: значок в круге и подпись.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.text,
    required this.color,
    this.emphasize = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 14, color: color),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
