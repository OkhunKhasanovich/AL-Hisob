import 'package:url_launcher/url_launcher.dart';

import '../../../core/domain/sms_status.dart';
import '../domain/sms_sender.dart';

/// Открывает системное окно SMS с готовым текстом; отправляет сам
/// пользователь. Единственный способ на iOS и запасной — на Android.
class ComposerSmsSender implements SmsSender {
  @override
  bool get silent => false;

  @override
  bool get supportsSimSelection => false;

  // Разрешения не нужны: сообщение отправляет системное приложение.
  @override
  Future<SmsPermissions> permissions() async =>
      const SmsPermissions(canSend: true, canListSims: false);

  @override
  Future<SmsPermissions> requestPermissions() => permissions();

  @override
  Future<List<SimInfo>> listSims() async => const [];

  @override
  Future<SmsSendResult> send({
    required String phone,
    required String body,
    int? subscriptionId,
  }) async {
    final uri = composerUri(phone, body);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return opened
          ? const SmsSendResult(SmsStatus.composerOpened)
          : const SmsSendResult.failed('cannot_open_composer');
    } catch (e) {
      return SmsSendResult.failed('$e');
    }
  }

  @override
  Future<void> openAppSettings() async {}
}

/// `sms:+998901234567?body=...` — на iOS разделитель `&`/`?` различается
/// между версиями, `?body=` поддерживают и iOS, и Android.
Uri composerUri(String phone, String body) =>
    Uri(scheme: 'sms', path: phone, queryParameters: {'body': body});
