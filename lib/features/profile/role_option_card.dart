import 'package:flutter/material.dart';

import '../../core/domain/shop_role.dart';
import '../../core/l10n/l10n.dart';
import 'shop_role_l10n.dart';

class RoleOptionCard extends StatelessWidget {
  const RoleOptionCard({
    super.key,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final ShopRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    role.icon,
                    size: 32,
                    color: selected ? scheme.onPrimaryContainer : scheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role.label(l10n),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: selected ? scheme.onPrimaryContainer : null,
                          ),
                        ),
                        if (role.description(l10n) case final description?)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: selected
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      key: ValueKey(selected),
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
