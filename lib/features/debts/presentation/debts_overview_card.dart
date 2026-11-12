import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../domain/debt_filter.dart';
import '../domain/debt_trend.dart';
import 'debt_trend_backdrop.dart';

/// Высота полосы графика в подробном виде: слева сводка, справа график.
const _bandHeight = 68.0;
const _morphDuration = Duration(milliseconds: 480);
const _statSize = 28.0;

/// Верхняя карточка экрана «Долги»: сколько вам должны всего, сколько должников и сколько
/// из них просрочено. Два вида, переключаются двойным нажатием:
///
/// * подробный — сумма, сводка и линия динамики за неделю;
/// * тонкий — одна узкая полоса без графика.
///
/// Переход — настоящее перетекание, а не подмена: подпись и сумма остаются на месте и плавно
/// уменьшаются, сводка уезжает вправо, график растворяется, а высота карточки меняется вместе
/// с ними. Нажатие на счётчик просрочки включает и выключает фильтр «Просроченные».
class DebtsOverviewCard extends StatefulWidget {
  const DebtsOverviewCard({
    super.key,
    required this.overview,
    this.trend,
    this.initialCompact = false,
    this.onCompactChanged,
    this.overdueSelected = false,
    this.onOverdueTap,
  });

  final DebtsOverview overview;

  /// Динамика общего долга; `null` — график не рисуется.
  final DebtTrend? trend;

  /// С какого вида начинать (запоминается между запусками).
  final bool initialCompact;

  /// Вызывается после переключения вида — чтобы сохранить выбор.
  final ValueChanged<bool>? onCompactChanged;

  /// Фильтр «Просроченные» сейчас включён (счётчик подсвечивается).
  final bool overdueSelected;

  /// Нажатие на счётчик просрочки; `null` — счётчик не нажимается.
  final VoidCallback? onOverdueTap;

  @override
  State<DebtsOverviewCard> createState() => _DebtsOverviewCardState();
}

class _DebtsOverviewCardState extends State<DebtsOverviewCard> with SingleTickerProviderStateMixin {
  late bool _compact = widget.initialCompact;

  /// 0 — подробный вид, 1 — тонкий.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: _morphDuration,
    value: _compact ? 1 : 0,
  );

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    _compact = !_compact;
    // Можно нажать снова посреди перехода: карточка плавно развернётся с того места, где она есть.
    _morph.animateTo(_compact ? 1 : 0, curve: Curves.easeInOutCubicEmphasized);
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
                LayoutBuilder(
                  builder: (context, constraints) => AnimatedBuilder(
                    animation: _morph,
                    builder: (context, _) => _Layout(
                      t: _morph.value,
                      width: constraints.maxWidth,
                      overview: widget.overview,
                      trend: widget.trend,
                      overdueSelected: widget.overdueSelected,
                      onOverdueTap: widget.onOverdueTap,
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

/// Высота одной строки текста с учётом масштаба шрифта в системе.
double _lineHeight(BuildContext context, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.height;
}

double _textWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// Все элементы карточки одним слоем: положение, размер и прозрачность каждого — функция
/// прогресса [t] (0 — подробный вид, 1 — тонкий). Поэтому элементы не накладываются ни в одной
/// точке перехода и не «прыгают».
class _Layout extends StatelessWidget {
  const _Layout({
    required this.t,
    required this.width,
    required this.overview,
    required this.trend,
    required this.overdueSelected,
    required this.onOverdueTap,
  });

  final double t;
  final double width;
  final DebtsOverview overview;
  final DebtTrend? trend;
  final bool overdueSelected;
  final VoidCallback? onOverdueTap;

  /// Доля перехода для элемента, который начинает позже или заканчивает раньше остальных.
  double _stage(double begin, double end) =>
      Interval(begin, end, curve: Curves.easeInOut).transform(t.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final amountBase = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onPrimaryContainer,
    );
    final labelBig = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
    );
    final labelSmall = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
    );

    // Размеры двух видов.
    const labelHeightBig = 20.0;
    final labelHeightSmall = _lineHeight(context, labelSmall);
    final amountHeightBig = _lineHeight(context, amountBase?.copyWith(fontSize: 32));
    final amountHeightSmall = _lineHeight(context, amountBase?.copyWith(fontSize: 24));
    final heightBig = 16 + labelHeightBig + 2 + amountHeightBig + 8 + _bandHeight + 12;
    final heightSmall = (10 + labelHeightSmall + amountHeightSmall + 10).clamp(_statSize + 20, 200.0);

    final main = Curves.linear.transform(t.clamp(0.0, 1.0)); // t уже со своей кривой
    final height = lerpDouble(heightBig, heightSmall, main)!;

    // Подпись и сумма: остаются у левого края, уменьшаются и подтягиваются вверх.
    final labelTop = lerpDouble(16, 10, main)!;
    final labelHeight = lerpDouble(labelHeightBig, labelHeightSmall, main)!;
    final amountTop = labelTop + labelHeight + lerpDouble(2, 0, main)!;
    final amountSize = lerpDouble(32, 24, main)!;

    // Справа в тонком виде стоит сводка: сумме остаётся меньше места.
    final statsWidth = _statsWidth(context);
    // Сначала сумма освобождает место справа (до половины перехода)…
    final amountWidth =
        lerpDouble(width - 40, width - 36 - statsWidth - 12, _stage(0, 0.5))!.clamp(40.0, double.infinity);

    // …сводка сначала едет вправо по низу карточки (под суммой), и только потом поднимается
    // на свою строку справа. Так путь сводки не пересекает сумму ни в какой момент.
    final statsX = _stage(0.15, 0.6);
    final statsY = _stage(0.5, 1);
    final statsAlign = Alignment(lerpDouble(-1, 1, statsX)!, lerpDouble(1, 0, statsY)!);
    final statsPadding = EdgeInsets.fromLTRB(
      lerpDouble(20, 0, statsX)!,
      0,
      lerpDouble(20, 16, statsX)!,
      lerpDouble(6, 0, statsY)!,
    );

    // График растворяется в первой половине перехода и больше не рисуется.
    final chartOpacity = 1 - _stage(0, 0.5);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          if (trend != null && chartOpacity > 0)
            Positioned.fill(
              child: Opacity(
                opacity: chartOpacity,
                child: DebtTrendBackdrop(trend: trend!, bandHeight: _bandHeight, bottomInset: 12),
              ),
            ),
          Positioned(
            left: 20,
            top: labelTop,
            height: labelHeight,
            right: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.debtsTotalLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle.lerp(labelBig, labelSmall, main),
              ),
            ),
          ),
          Positioned(
            left: 20,
            top: amountTop,
            width: amountWidth,
            child: _Amount(
              amount: overview.totalOwed,
              currency: l10n.currencySum,
              style: amountBase?.copyWith(fontSize: amountSize),
              maxWidth: amountWidth,
              // С середины карточки сумма гаснет к правому краю — там график; в тонком виде не нужно.
              fadeFromX: width / 2 - 20,
              fadeEndAlpha: lerpDouble(0.22, 1, _stage(0, 0.6))!,
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: statsPadding,
              child: Align(
                alignment: statsAlign,
                child: _stats(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _statsWidth(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800);
    var w = _statSize + 7 + _textWidth(context, '${overview.debtorCount}', style);
    if (overview.overdueCount > 0) {
      w += 14 + 8 + _statSize + 7 + _textWidth(context, '${overview.overdueCount}', style);
    }
    return w;
  }

  /// Значки с числами в одну строку; полная подпись — для экранных дикторов.
  Widget _stats(BuildContext context) {
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
            onColor: scheme.onError,
            emphasize: true,
            selected: overdueSelected,
            onTap: onOverdueTap,
          ),
        ],
      ],
    );
  }
}

/// Сумма долга: с середины карточки число и «сум» плавно становятся прозрачнее к правому краю.
class _Amount extends StatelessWidget {
  const _Amount({
    required this.amount,
    required this.currency,
    required this.style,
    required this.maxWidth,
    required this.fadeFromX,
    required this.fadeEndAlpha,
  });

  final int amount;
  final String currency;
  final TextStyle? style;
  final double maxWidth;

  /// Откуда (в координатах текста) начинается затухание.
  final double fadeFromX;

  /// Прозрачность у правого края: 0.22 — затухает, 1 — без затухания.
  final double fadeEndAlpha;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
            final scale = bounds.width <= maxWidth ? 1.0 : maxWidth / bounds.width;
            final start = (fadeFromX / scale / bounds.width).clamp(0.0, 1.0);
            return LinearGradient(
              colors: [Colors.white, Colors.white, Colors.white.withValues(alpha: fadeEndAlpha)],
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
            style: style,
          ),
        ),
      ),
    );
  }
}

/// Значок в круге и число; подпись целиком — в семантике. Если задан [onTap], счётчик
/// нажимается, а при [selected] подсвечивается сплошным кругом (фильтр включён).
class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onColor,
    this.emphasize = false,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color color;
  final Color? onColor;
  final bool emphasize;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = selected ? (onColor ?? color) : color;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color : color.withValues(alpha: 0.16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: iconColor),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          '$value',
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: emphasize || selected ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    );

    if (onTap != null) {
      // Зона нажатия крупнее значка.
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: content),
      );
    }

    return Semantics(
      label: label,
      button: onTap != null,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(child: content),
    );
  }
}
