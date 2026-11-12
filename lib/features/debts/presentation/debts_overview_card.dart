import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_trend.dart';
import 'debt_trend_backdrop.dart';

/// Высота нижней полосы подробного вида: слева сводка, справа график.
const _bandHeight = 68.0;
const _cardPadding = EdgeInsets.fromLTRB(20, 16, 20, 12);
const _compactPadding = EdgeInsets.fromLTRB(20, 10, 16, 10);
const _morph = Duration(milliseconds: 340);

/// Верхняя карточка экрана «Долги»: сколько вам должны всего, сколько должников и сколько
/// из них просрочено. Два вида, переключаются двойным нажатием (плавно, с изменением высоты):
///
/// * подробный — сумма, сводка и линия динамики за неделю;
/// * тонкий — одна компактная полоса без графика.
class DebtsOverviewCard extends StatefulWidget {
  const DebtsOverviewCard({
    super.key,
    required this.overview,
    this.trend,
    this.initialCompact = false,
    this.onCompactChanged,
  });

  final DebtsOverview overview;

  /// Динамика общего долга; `null` — график не рисуется.
  final DebtTrend? trend;

  /// С какого вида начинать (запоминается между запусками).
  final bool initialCompact;

  /// Вызывается после переключения вида — чтобы сохранить выбор.
  final ValueChanged<bool>? onCompactChanged;

  @override
  State<DebtsOverviewCard> createState() => _DebtsOverviewCardState();
}

class _DebtsOverviewCardState extends State<DebtsOverviewCard> {
  late bool _compact = widget.initialCompact;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _compact = !_compact);
    widget.onCompactChanged?.call(_compact);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(28);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GestureDetector(
        key: const ValueKey('overview-card'),
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _toggle,
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
                // Высота меняется плавно, а содержимое перетекает: уходящий вид растворяется
                // поверх, приходящий проявляется и задаёт новую высоту.
                AnimatedSize(
                  duration: _morph,
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: _morph,
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        for (final old in previous) Positioned(top: 0, left: 0, right: 0, child: old),
                        ?current,
                      ],
                    ),
                    child: _compact
                        ? _CompactBody(key: const ValueKey('overview-compact'), overview: widget.overview)
                        : _DetailedBody(
                            key: const ValueKey('overview-detailed'),
                            overview: widget.overview,
                            trend: widget.trend,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Значки с числами в одну строку; полная подпись — для экранных дикторов.
Widget _stats(BuildContext context, DebtsOverview overview) {
  final l10n = context.l10n;
  final scheme = Theme.of(context).colorScheme;
  return Row(
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
}

/// Подробный вид: подпись, сумма, сводка слева и график динамики справа.
class _DetailedBody extends StatelessWidget {
  const _DetailedBody({super.key, required this.overview, required this.trend});

  final DebtsOverview overview;
  final DebtTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasChart = trend != null;
    final stats = _stats(context, overview);

    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          if (trend != null)
            Positioned.fill(
              child: DebtTrendBackdrop(
                trend: trend!,
                bandHeight: _bandHeight,
                bottomInset: _cardPadding.bottom,
              ),
            ),
          Padding(
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
          ),
        ],
      ),
    );
  }
}

/// Тонкий вид: слева подпись и сумма, справа сводка. Без графика.
class _CompactBody extends StatelessWidget {
  const _CompactBody({super.key, required this.overview});

  final DebtsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: _compactPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.debtsTotalLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                    ),
                  ),
                  _Amount(amount: overview.totalOwed, currency: l10n.currencySum, fontSize: 24, fade: false),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _stats(context, overview),
          ],
        ),
      ),
    );
  }
}

/// Сумма долга: с середины карточки число и «сум» плавно становятся прозрачнее к правому краю.
class _Amount extends StatelessWidget {
  const _Amount({required this.amount, required this.currency, this.fontSize = 32, this.fade = true});

  final int amount;
  final String currency;
  final double fontSize;

  /// Затухание к правому краю карточки (в подробном виде, где справа график).
  final bool fade;

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
                if (!fade) return const LinearGradient(colors: [Colors.white, Colors.white]).createShader(bounds);
                // FittedBox сжимает длинную сумму: пересчитываем середину карточки в её единицах.
                final scale = bounds.width <= innerWidth ? 1.0 : innerWidth / bounds.width;
                final start = (halfX / scale / bounds.width).clamp(0.0, 1.0);
                return LinearGradient(
                  colors: [
                    Colors.white,
                    Colors.white,
                    Colors.white.withValues(alpha: 0.22),
                  ],
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
                  fontSize: fontSize,
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
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.16)),
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
