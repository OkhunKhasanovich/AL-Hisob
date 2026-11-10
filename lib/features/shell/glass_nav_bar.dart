import 'package:flutter/material.dart';

import '../../core/widgets/glass.dart';

class GlassNavItem {
  const GlassNavItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;

  /// Подпись не рисуется, но остаётся в подсказке и для экранных дикторов.
  final String label;
}

/// Высота самой «таблетки» вкладок.
const glassNavHeight = 56.0;

/// Отступ таблетки от нижнего края экрана (поверх системной области жестов).
const glassNavGap = 12.0;

/// Плавающая панель вкладок из матового стекла: только значки, активная вкладка
/// подсвечена скользящим пятном. Содержимое страниц прокручивается под панелью и
/// просвечивает сквозь размытие.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<GlassNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final background = theme.scaffoldBackgroundColor;

    return DecoratedBox(
      // Под панелью фон плавно темнеет, чтобы текст страниц не спорил со значками.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background.withValues(alpha: 0), background.withValues(alpha: 0.92)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, glassNavGap + bottom),
        child: GlassPanel(
          child: SizedBox(
            height: glassNavHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / items.length;
                return Stack(
                  children: [
                    // Скользящее пятно под активной вкладкой.
                    AnimatedPositioned(
                      key: const ValueKey('nav-indicator'),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      left: selectedIndex * itemWidth + 6,
                      top: 6,
                      width: itemWidth - 12,
                      height: glassNavHeight - 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.primary.withValues(alpha: 0.34),
                              scheme.primary.withValues(alpha: 0.12),
                            ],
                          ),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.35),
                              blurRadius: 14,
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: _NavButton(
                              item: items[i],
                              selected: i == selectedIndex,
                              onTap: () => onSelected(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Tooltip(
        message: item.label,
        child: InkResponse(
          radius: 30,
          onTap: onTap,
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.12 : 1,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 24,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Поднимает плавающую кнопку страницы над стеклянной панелью вкладок: страницы
/// заходят под панель, и без этого кнопка оказалась бы прямо на ней.
Widget liftAboveNav(BuildContext context, Widget fab) =>
    Padding(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom), child: fab);
