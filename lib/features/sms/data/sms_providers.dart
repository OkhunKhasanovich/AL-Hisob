import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/settings_providers.dart';
import '../domain/sms_sender.dart';
import 'android_sms_sender.dart';
import 'composer_sms_sender.dart';
import 'sms_log_repository.dart';
import 'sms_service.dart';
import 'sms_templates_repository.dart';

/// Android — прямая отправка через SIM; остальные платформы — системное окно SMS.
/// Переопределяется в тестах.
final smsSenderProvider = Provider<SmsSender>(
  (ref) => Platform.isAndroid ? AndroidSmsSender() : ComposerSmsSender(),
);

final smsLogRepositoryProvider = Provider<SmsLogRepository>(
  (ref) => SmsLogRepository(ref.watch(appDatabaseProvider)),
);

final smsTemplatesRepositoryProvider = Provider<SmsTemplatesRepository>(
  (ref) => SmsTemplatesRepository(ref.watch(appDatabaseProvider)),
);

final smsServiceProvider = Provider<SmsService>(
  (ref) => SmsService(
    sender: ref.watch(smsSenderProvider),
    log: ref.watch(smsLogRepositoryProvider),
  ),
);

/// Журнал SMS одного должника.
final smsLogsProvider = StreamProvider.autoDispose.family<List<SmsLog>, String>(
  (ref, debtorId) => ref.watch(smsLogRepositoryProvider).watchForDebtor(debtorId),
);

/// Шаблоны всех четырёх языков (после правок — обновляется вручную через invalidate).
final smsTemplatesProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(smsTemplatesRepositoryProvider).all(),
);

/// SIM-карты телефона (пусто, если нет разрешения или платформа не поддерживает).
final simsProvider = FutureProvider.autoDispose<List<SimInfo>>(
  (ref) => ref.watch(smsSenderProvider).listSims(),
);
