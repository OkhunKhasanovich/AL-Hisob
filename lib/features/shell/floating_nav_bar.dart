import 'package:flutter/material.dart';

class FloatingNavItem {
  const FloatingNavItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;

  /// Подпись не рисуется, но остаётся в подсказке и для экранных дикторов.
  final String label;
}

/// Высота самой «таблетки» вкладок.
const floatingNavHeight = 56.0;

/// Плавающая панель вкладок в форме «таблетки»: скруглённая, с отступами от краёв экрана,
/// только значки; активная вкладка отмечена скользящим пятном. Цвета обычные, сплошные.
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
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 6, 20, 12 + bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: SizedBox(
          height: floatingNavHeight,
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
                    height: floatingNavHeight - 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(22),
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
        child: InkResponse(
          radius: 30,
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
