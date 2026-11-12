import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/section_app_bar.dart';
import '../../core/router/routes.dart';
import '../../core/settings/settings_providers.dart';
import '../debts/presentation/debt_settings_section.dart';
import '../debts/presentation/demo_data_section.dart';
import '../auth/presentation/account_tile.dart';
import '../sync/presentation/sync_tile.dart';
import '../profile/profile_card.dart';
import '../update/presentation/update_tile.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final selected = ref.watch(localeProvider) ??
        resolveLocale(Localizations.localeOf(context), AppLocalizations.supportedLocales);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: SectionAppBar(title: l10n.moreTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          const ProfileCard(),
          const AccountTile(),
          const SyncTile(),
          const SizedBox(height: 32),
          Text(l10n.settingsLanguage, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final locale in AppLocalizations.supportedLocales)
                ChoiceChip(
                  label: Text(languageNames[locale.languageCode] ?? locale.languageCode),
                  selected: selected.languageCode == locale.languageCode,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    ref.read(localeProvider.notifier).select(locale);
                  },
                ),
            ],
          ),
          const SizedBox(height: 32),
          Text(l10n.settingsTheme, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.brightness_auto_rounded),
                label: Text(l10n.themeSystem),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_rounded),
                label: Text(l10n.themeLight),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode_rounded),
                label: Text(l10n.themeDark),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              ref.read(themeModeProvider.notifier).select(s.first);
            },
          ),
          const SizedBox(height: 32),
          const DebtSettingsSection(),
          const SizedBox(height: 24),
          const DemoDataSection(),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sms_rounded),
            title: Text(l10n.smsTemplatesTitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.smsTemplates),
          ),
          const SizedBox(height: 16),
          const UpdateTile(),
        ],
      ),
    );
  }
}
