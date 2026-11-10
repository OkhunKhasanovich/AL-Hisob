import '../../../core/domain/sms_status.dart';
import '../domain/bulk_sms_runner.dart';
import '../domain/sms_sender.dart';
import 'sms_log_repository.dart';

/// Отправка + запись в журнал. Любой исход (успех, ошибка, открыто окно SMS)
/// попадает в журнал должника.
class SmsService {
  SmsService({required this.sender, required this.log});

  final SmsSender sender;
  final SmsLogRepository log;

  Future<SmsSendResult> send({
    required String debtorId,
    required String phone,
    required String body,
    int? subscriptionId,
  }) async {
    SmsSendResult result;
    try {
      result = await sender.send(phone: phone, body: body, subscriptionId: subscriptionId);
    } catch (e) {
      result = SmsSendResult.failed('$e');
    }
    await log.add(
      debtorId: debtorId,
      phone: phone,
      body: body,
      status: result.status,
      error: result.error,
    );
    return result;
  }

  /// Для [BulkSmsRunner].
  Future<SmsSendResult> sendItem(BulkSmsItem item, {int? subscriptionId}) => send(
        debtorId: item.debtorId,
        phone: item.phone,
        body: item.body,
        subscriptionId: subscriptionId,
      );
}

/// Человекочитаемая причина по коду ошибки (для журнала и сообщений).
String smsErrorKey(String? error) => switch (error) {
      'no_permission' => 'no_permission',
      'radio_off' => 'radio_off',
      'no_service' => 'no_service',
      'timeout' => 'timeout',
      null => 'unknown',
      _ => 'other',
    };

extension SmsStatusX on SmsStatus {
  bool get isOk => this != SmsStatus.failed;
}
