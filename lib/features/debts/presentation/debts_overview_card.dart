import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/glass.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_trend.dart';
import 'debt_trend_backdrop.dart';

/// Высота нижней полосы: слева сводка, справа график.
const _bandHeight = 68.0;
const _cardPadding = EdgeInsets.fromLTRB(20, 16, 20, 12);

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

    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: scheme.primary.withValues(alpha: dark ? 0.40 : 0.38)),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Stack(
              children: [
                // Чёрное полупрозрачное стекло (как карточки должников), фон приложения просвечивает.
                Positioned.fill(
                  child: ColoredBox(color: glassBase(Theme.of(context).brightness, opacity: 0.5)),
                ),
                // Зелёный оттенок в левом верхнем углу гаснет к правому нижнему.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primary.withValues(alpha: dark ? 0.26 : 0.30),
                          scheme.primary.withValues(alpha: dark ? 0.03 : 0.06),
                        ],
                        stops: const [0, 0.75],
                      ),
                    ),
                  ),
                ),
                // Мягкий блик в левом верхнем углу.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.9, -1.1),
                        radius: 1.1,
                        colors: [
                          Colors.white.withValues(alpha: dark ? 0.06 : 0.25),
                          Colors.white.withValues(alpha: 0),
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

    // Только значки с числами, в одну строку; полная подпись — для экранных дикторов.
    final stats = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Stat(
          key: const ValueKey('stat-debtors'),
          icon: Icons.groups_rounded,
          value: overview.debtorCount,
          label: l10n.debtsCountLabel(overview.debtorCount),
          color: scheme.onPrimaryContainer,
        ),
        if (overview.overdueCount > 0) ...[
          const SizedBox(width: 14),
          _Stat(
            key: const ValueKey('stat-overdue'),
            icon: Icons.schedule_rounded,
            value: overview.overdueCount,
            label: l10n.debtsOverdueLabel(overview.overdueCount),
            color: scheme.error,
            emphasize: true,
          ),
        ],
      ],
    );

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
          _Amount(amount: overview.totalOwed, currency: l10n.currencySum),
          const SizedBox(height: 8),
          if (hasChart)
            // Сводка слева у нижнего края полосы; с 40% ширины карточки начинается график.
            SizedBox(
              height: _bandHeight,
              child: Align(alignment: Alignment.bottomLeft, child: stats),
            )
          else
            stats,
        ],
      ),
    );
  }
}

/// Сумма долга: с середины карточки число и «сум» плавно становятся прозрачнее к правому краю.
class _Amount extends StatelessWidget {
  const _Amount({required this.amount, required this.currency});

  final int amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final innerWidth = constraints.maxWidth;
        final cardWidth = innerWidth + _cardPadding.horizontal;
        // Середина карточки в координатах текста (текст начинается после левого отступа).
        final halfX = cardWidth / 2 - _cardPadding.left;

        return TweenAnimationBuilder<double>(
          tween: Tween(end: amount.toDouble()),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                // FittedBox сжимает длинную сумму: пересчитываем середину карточки в её единицах.
                final scale = bounds.width <= innerWidth ? 1.0 : innerWidth / bounds.width;
                final start = (halfX / scale / bounds.width).clamp(0.0, 1.0);
                return LinearGradient(
                  colors: [Colors.white, Colors.white, Colors.white.withValues(alpha: 0.22)],
                  stops: [0, start, 1],
                ).createShader(bounds);
              },
              child: Text.rich(
                TextSpan(
                  text: formatAmount(value.round()),
                  children: [
                    TextSpan(
                      text: ' $currency',
                      style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Значок в круге и число; подпись целиком — в семантике.
class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.emphasize = false,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(icon, size: 16, color: color),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '$value',
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
