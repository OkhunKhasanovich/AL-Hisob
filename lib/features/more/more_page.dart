import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/router/routes.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/widgets/section_app_bar.dart';
import '../../core/widgets/settings_group.dart';
import '../auth/presentation/account_tile.dart';
import '../auth/presentation/login_prompt.dart' show serverConfiguredProvider;
import '../debts/presentation/debt_settings_section.dart';
import '../debts/presentation/demo_data_section.dart';
import '../profile/profile_card.dart';
import '../sync/presentation/sync_tile.dart';
import '../update/presentation/update_tile.dart';

/// Вкладка «Ещё»: профиль, аккаунт, оформление, настройки книги, обновление.
/// Блоки — компактные карточки с плотными строками.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = ref.watch(localeProvider) ??
        resolveLocale(Localizations.localeOf(context), AppLocalizations.supportedLocales);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: SectionAppBar(title: l10n.moreTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          const ProfileCard(),
          if (ref.watch(serverConfiguredProvider))
            const SettingsGroup(children: [AccountTile(), SyncTile()]),
          SettingsGroup(
            children: [
              // Строка открывает шторку выбора языка; справа — текущий язык.
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(l10n.settingsLanguage),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      languageNames[selected.languageCode] ?? selected.languageCode,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: () => _pickLanguage(context, ref, selected),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(l10n.settingsTheme),
                trailing: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity(horizontal: -2, vertical: -2),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(Icons.brightness_auto_rounded, size: 18),
                      tooltip: l10n.themeSystem,
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode_rounded, size: 18),
                      tooltip: l10n.themeLight,
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_rounded, size: 18),
                      tooltip: l10n.themeDark,
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (s) {
                    HapticFeedback.selectionClick();
                    ref.read(themeModeProvider.notifier).select(s.first);
                  },
                ),
              ),
            ],
          ),
          DebtSettingsSection(
            extra: [
              ListTile(
                leading: const Icon(Icons.campaign_rounded),
                title: Text(l10n.bulkSmsTitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.bulkSms),
              ),
              ListTile(
                leading: const Icon(Icons.sms_rounded),
                title: Text(l10n.smsTemplatesTitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.smsTemplates),
              ),
            ],
          ),
          const SettingsGroup(children: [UpdateTile()]),
          const DemoDataSection(),
        ],
      ),
    );
  }
}

/// Шторка выбора языка: короткий список, отмечен текущий.
Future<void> _pickLanguage(BuildContext context, WidgetRef ref, Locale selected) {
  return showModalBottomSheet<void>(
    // Поверх панели вкладок, а не под ней.
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final locale in AppLocalizations.supportedLocales)
            ListTile(
              title: Text(languageNames[locale.languageCode] ?? locale.languageCode),
              trailing: selected.languageCode == locale.languageCode
                  ? Icon(Icons.check_rounded, color: Theme.of(sheetContext).colorScheme.primary)
                  : null,
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(localeProvider.notifier).select(locale);
                Navigator.of(sheetContext).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
