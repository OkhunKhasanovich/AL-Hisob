import 'package:flutter/material.dart';

class FloatingNavItem {
  const FloatingNavItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;

  /// Подпись не рисуется, но остаётся в подсказке и для экранных дикторов.
  final String label;
}

/// Высота ряда значков (без системного отступа снизу).
const floatingNavHeight = 56.0;

/// Панель вкладок во всю ширину экрана, прижатая к низу: скруглена только сверху, значки без подписей,
/// активная вкладка отмечена скользящим пятном. Фон продолжается под системными кнопками
/// навигации, а значки стоят выше них, поэтому ни пустой полосы, ни наложения нет.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<FloatingNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Место под системные кнопки или жестовую полосу Android.
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shadowColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: floatingNavHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / items.length;
              const indicatorWidth = 68.0;
              const indicatorHeight = 36.0;
              return Stack(
                children: [
                  // Скользящее пятно под активной вкладкой.
                  AnimatedPositioned(
                    key: const ValueKey('nav-indicator'),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: selectedIndex * itemWidth + (itemWidth - indicatorWidth) / 2,
                    top: (floatingNavHeight - indicatorHeight) / 2,
                    width: indicatorWidth,
                    height: indicatorHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(18),
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
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final FloatingNavItem item;
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
        // Без ripple и подсветки: при нажатии ничего не «просвечивает», меняется только активная вкладка.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.1 : 1,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 24,
                color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Поднимает плавающую кнопку страницы над панелью вкладок: страницы заходят под панель,
/// и без этого кнопка оказалась бы прямо на ней.
Widget liftAboveNav(BuildContext context, Widget fab) =>
    Padding(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom), child: fab);
