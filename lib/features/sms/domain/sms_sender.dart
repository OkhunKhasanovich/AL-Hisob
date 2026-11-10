import '../../../core/domain/sms_status.dart';

/// SIM-карта телефона (Android).
class SimInfo {
  const SimInfo({
    required this.subscriptionId,
    required this.slot,
    required this.name,
    required this.carrier,
    required this.isDefaultForSms,
  });

  final int subscriptionId;

  /// Номер слота: 0, 1...
  final int slot;
  final String name;
  final String carrier;
  final bool isDefaultForSms;

  /// Подпись для выбора: «SIM 1 · Ucell».
  String get label {
    final title = name.isNotEmpty ? name : carrier;
    return title.isEmpty ? 'SIM ${slot + 1}' : 'SIM ${slot + 1} · $title';
  }
}

/// Состояние разрешений на отправку SMS.
class SmsPermissions {
  const SmsPermissions({
    required this.canSend,
    required this.canListSims,
    this.blockedForever = false,
  });

  /// Есть SEND_SMS.
  final bool canSend;

  /// Есть READ_PHONE_STATE (нужно только для выбора SIM).
  final bool canListSims;

  /// Пользователь запретил и поставил «больше не спрашивать» —
  /// разрешить можно только в настройках телефона.
  final bool blockedForever;

  static const none = SmsPermissions(canSend: false, canListSims: false);
}

class SmsSendResult {
  const SmsSendResult(this.status, {this.error});

  const SmsSendResult.sent() : this(SmsStatus.sent);
  const SmsSendResult.failed(String error) : this(SmsStatus.failed, error: error);

  final SmsStatus status;
  final String? error;

  bool get isFailure => status == SmsStatus.failed;
}

/// Отправка SMS. Реализации:
/// * Android — напрямую через SIM телефона ([silent] == true);
/// * системное окно SMS (iOS и запасной вариант) — каждое сообщение
///   подтверждает пользователь;
/// * серверный SMS-шлюз — позже (этап 8+), если Google Play запретит
///   SMS-разрешения.
abstract interface class SmsSender {
  /// Отправляет без участия пользователя (можно делать массовую рассылку).
  bool get silent;

  /// Можно выбрать SIM.
  bool get supportsSimSelection;

  Future<SmsPermissions> permissions();

  /// Запрашивает недостающие разрешения.
  Future<SmsPermissions> requestPermissions();

  Future<List<SimInfo>> listSims();

  /// [phone] — в формате `+998901234567`. Никогда не бросает исключений:
  /// ошибки возвращаются как [SmsSendResult.failed].
  Future<SmsSendResult> send({
    required String phone,
    required String body,
    int? subscriptionId,
  });

  /// Открывает настройки приложения, где можно выдать разрешения.
  Future<void> openAppSettings();
}
