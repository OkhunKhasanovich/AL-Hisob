import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/settings/settings_providers.dart';
import '../../profile/profile_providers.dart';
import '../data/local_stats.dart';
import '../domain/auth_models.dart';
import '../domain/login_prompt_logic.dart';
import 'auth_controller.dart';

const _snoozedUntilKey = 'login_prompt_snoozed_until_ms';
const _afterDaysKey = 'login_prompt_after_days';
const _afterRecordsKey = 'login_prompt_after_records';
const _snoozeDaysKey = 'login_prompt_snooze_days';

/// Пороги предложения: значения из настроек (ключи `login_prompt_*`) или по умолчанию.
final loginPromptConfigProvider = FutureProvider<LoginPromptConfig>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  return LoginPromptConfig(
    afterDays: await settings.readInt(_afterDaysKey) ?? LoginPromptConfig.defaultAfterDays,
    afterRecords: await settings.readInt(_afterRecordsKey) ?? LoginPromptConfig.defaultAfterRecords,
    snoozeDays: await settings.readInt(_snoozeDaysKey) ?? LoginPromptConfig.defaultSnoozeDays,
  );
});

final localRecordCountProvider = StreamProvider<int>(
  (ref) => LocalStatsRepository(ref.watch(appDatabaseProvider)).watchRecordCount(),
);

/// До какого момента предложение отложено.
class LoginPromptSnooze extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async {
    final ms = await ref.watch(settingsRepositoryProvider).readInt(_snoozedUntilKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> snooze(Duration duration) async {
    final until = DateTime.now().add(duration);
    await ref.read(settingsRepositoryProvider).writeInt(_snoozedUntilKey, until.millisecondsSinceEpoch);
    state = AsyncData(until);
  }
}

final loginPromptSnoozeProvider =
    AsyncNotifierProvider<LoginPromptSnooze, DateTime?>(LoginPromptSnooze.new);

/// Показывать ли сейчас предложение войти.
final showLoginPromptProvider = Provider<bool>((ref) {
  final signedIn = ref.watch(authControllerProvider);
  // Пока не прочитали сохранённую сессию, не мигаем предложением.
  if (signedIn.isLoading) return false;
  final firstUse = ref.watch(shopProfileProvider).value?.createdAt;
  final records = ref.watch(localRecordCountProvider).value ?? 0;
  final snoozed = ref.watch(loginPromptSnoozeProvider);
  final config = ref.watch(loginPromptConfigProvider).value ?? const LoginPromptConfig();
  if (snoozed.isLoading) return false;

  return shouldShowLoginPrompt(
    now: DateTime.now(),
    firstUse: firstUse,
    recordCount: records,
    snoozedUntil: snoozed.value,
    signedIn: signedIn.value != null,
    serverConfigured: ref.watch(serverConfiguredProvider),
    config: config,
  );
});

/// Сервер настроен (`API_BASE_URL`). Переопределяется в тестах.
final serverConfiguredProvider = Provider<bool>((ref) => isServerConfigured);

/// Мягкое предложение «Войдите, чтобы не потерять данные».
class LoginPromptCard extends ConsumerWidget {
  const LoginPromptCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showLoginPromptProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final snoozeDays =
        ref.watch(loginPromptConfigProvider).value?.snoozeDays ?? LoginPromptConfig.defaultSnoozeDays;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.cloud_sync_rounded, color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.loginPromptTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                l10n.loginPromptBody,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => ref
                        .read(loginPromptSnoozeProvider.notifier)
                        .snooze(Duration(days: snoozeDays)),
                    child: Text(l10n.updateLater),
                  ),
                  FilledButton(
                    onPressed: () => context.push(Routes.login),
                    child: Text(l10n.accountSignIn),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
