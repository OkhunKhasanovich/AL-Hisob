import 'package:flutter/services.dart';

import '../../../core/domain/sms_status.dart';
import '../domain/sms_sender.dart';

/// Отправка SMS напрямую через SIM телефона (Android, `SmsManager`).
/// Нативная часть — `android/.../SmsBridge.kt`.
class AndroidSmsSender implements SmsSender {
  AndroidSmsSender({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('uz.alsavdogar.app/sms');

  final MethodChannel _channel;

  @override
  bool get silent => true;

  @override
  bool get supportsSimSelection => true;

  @override
  Future<SmsPermissions> permissions() => _call('permissions');

  @override
  Future<SmsPermissions> requestPermissions() => _call('requestPermissions');

  Future<SmsPermissions> _call(String method) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(method);
      return _parsePermissions(raw);
    } on PlatformException {
      return SmsPermissions.none;
    } on MissingPluginException {
      return SmsPermissions.none;
    }
  }

  @override
  Future<List<SimInfo>> listSims() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('listSims');
      return [
        for (final m in raw ?? const <Map<Object?, Object?>>[])
          SimInfo(
            subscriptionId: m['subscriptionId']! as int,
            slot: m['slot']! as int,
            name: (m['name'] as String?) ?? '',
            carrier: (m['carrier'] as String?) ?? '',
            isDefaultForSms: (m['isDefaultForSms'] as bool?) ?? false,
          ),
      ]..sort((a, b) => a.slot.compareTo(b.slot));
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<SmsSendResult> send({
    required String phone,
    required String body,
    int? subscriptionId,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('sendSms', {
        'phone': phone,
        'body': body,
        'subscriptionId': subscriptionId,
      });
      return parseSendResult(raw);
    } on PlatformException catch (e) {
      return SmsSendResult.failed(e.message ?? e.code);
    } on MissingPluginException {
      return const SmsSendResult.failed('not_supported');
    }
  }

  @override
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      // нечего делать: настройки не открылись
    } on MissingPluginException {
      // то же
    }
  }
}

SmsPermissions _parsePermissions(Map<String, Object?>? raw) => SmsPermissions(
      canSend: (raw?['canSend'] as bool?) ?? false,
      canListSims: (raw?['canListSims'] as bool?) ?? false,
      blockedForever: (raw?['blockedForever'] as bool?) ?? false,
    );

/// Разбор ответа нативного `sendSms`. Вынесено для тестов.
SmsSendResult parseSendResult(Map<String, Object?>? raw) {
  switch (raw?['status']) {
    case 'sent':
      return const SmsSendResult.sent();
    case 'no_permission':
      return const SmsSendResult.failed('no_permission');
    case 'failed':
      return SmsSendResult(
        SmsStatus.failed,
        error: (raw?['message'] as String?) ?? 'failed',
      );
    default:
      return const SmsSendResult.failed('unknown_response');
  }
}
