import 'package:flutter/material.dart';

/// Блок настроек: маленький заголовок и скруглённая карточка с плотными строками.
/// Строки (`ListTile`) внутри получают единые компактные отступы без своих настроек.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                title!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: ListTileTheme.merge(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              horizontalTitleGap: 12,
              minLeadingWidth: 24,
              minVerticalPadding: 6,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}
