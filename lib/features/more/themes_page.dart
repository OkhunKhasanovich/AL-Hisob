import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/theme/glass_style.dart';
import '../../core/theme/theme_style.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/settings_group.dart';

/// Подпись стиля для списка настроек.
String themeStyleLabel(AppLocalizations l10n, ThemeStyle style) => switch (style) {
      ThemeStyle.classic => l10n.themeStyleClassic,
      ThemeStyle.liquidGlass => l10n.themeStyleGlass,
    };

/// Раздел «Темы»: стиль оформления (с образцами) и светлая/тёмная тема.
class ThemesPage extends ConsumerWidget {
  const ThemesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final style = ref.watch(themeStyleProvider);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.themesTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              l10n.themeStyleSection,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in ThemeStyle.values) ...[
                Expanded(
                  child: _StyleOption(
                    key: ValueKey('theme-style-${s.name}'),
                    style: s,
                    selected: style == s,
                    title: themeStyleLabel(l10n, s),
                    description: s == ThemeStyle.classic ? l10n.themeStyleClassicDesc : l10n.themeStyleGlassDesc,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(themeStyleProvider.notifier).select(s);
                    },
                  ),
                ),
                if (s != ThemeStyle.values.last) const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 20),
          SettingsGroup(
            title: l10n.themeModeSection,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    // Без значков: три подписи («Как в системе», «Светлая», «Тёмная») помещаются целиком.
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l10n.themeSystem, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(l10n.themeLight, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(l10n.themeDark, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) {
                      HapticFeedback.selectionClick();
                      ref.read(themeModeProvider.notifier).select(s.first);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Образец стиля с названием; выбранный отмечен рамкой и галочкой.
class _StyleOption extends StatelessWidget {
  const _StyleOption({
    super.key,
    required this.style,
    required this.selected,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final ThemeStyle style;
  final bool selected;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 132,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _Preview(style: style)),
                      if (selected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
              child: Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Мини-образец: фон, две «карточки» и панель вкладок в выбранном стиле (без текста).
class _Preview extends StatelessWidget {
  const _Preview({required this.style});

  final ThemeStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = style == ThemeStyle.liquidGlass;
    final glassStyle = GlassStyle.forBrightness(Theme.of(context).brightness);
    // Образец стекла рисуется своими красками, даже если сейчас включён обычный стиль.
    Widget card(double width) => glass
        ? Theme(
            data: Theme.of(context).copyWith(extensions: [glassStyle]),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(height: 26, width: width),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(height: 26, width: width),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (glass)
          Theme(
            data: Theme.of(context).copyWith(extensions: [glassStyle]),
            child: const GlassBackdrop(),
          )
        else
          ColoredBox(color: scheme.surface),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card(double.infinity),
              const SizedBox(height: 8),
              card(double.infinity),
              const SizedBox(height: 8),
              card(60),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 22,
          child: glass
              ? Theme(
                  data: Theme.of(context).copyWith(extensions: [glassStyle]),
                  child: GlassSurface(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    strong: true,
                    child: const SizedBox.expand(),
                  ),
                )
              : ColoredBox(color: scheme.surfaceContainerHigh),
        ),
      ],
    );
  }
}
