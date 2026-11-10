/// Когда мягко предлагать войти. Значения можно менять в настройках
/// (ключи `login_prompt_*`), по умолчанию — через 3 дня или 20 записей.
class LoginPromptConfig {
  const LoginPromptConfig({
    this.afterDays = defaultAfterDays,
    this.afterRecords = defaultAfterRecords,
    this.snoozeDays = defaultSnoozeDays,
  });

  static const defaultAfterDays = 3;
  static const defaultAfterRecords = 20;
  static const defaultSnoozeDays = 3;

  final int afterDays;
  final int afterRecords;
  final int snoozeDays;
}

/// Нужно ли показать предложение войти.
///
/// Показываем, если пользователь не вошёл, сервер настроен, предложение не отложено
/// и выполнено одно из условий: с первого использования прошло [LoginPromptConfig.afterDays]
/// дней либо накопилось [LoginPromptConfig.afterRecords] записей.
bool shouldShowLoginPrompt({
  required DateTime now,
  required DateTime? firstUse,
  required int recordCount,
  required DateTime? snoozedUntil,
  required bool signedIn,
  required bool serverConfigured,
  LoginPromptConfig config = const LoginPromptConfig(),
}) {
  if (signedIn || !serverConfigured || firstUse == null) return false;
  if (snoozedUntil != null && now.isBefore(snoozedUntil)) return false;
  final daysPassed = now.difference(firstUse) >= Duration(days: config.afterDays);
  final enoughRecords = recordCount >= config.afterRecords;
  return daysPassed || enoughRecords;
}
