import 'package:drift/drift.dart';

import '../../domain/sms_status.dart';
import '../sync_columns.dart';
import 'debts.dart';

/// Шаблоны SMS, изменённые пользователем (по одному на язык).
/// Если строки нет — используется шаблон по умолчанию из кода.
class SmsTemplates extends Table with SyncColumns {
  /// Код языка шаблона: uz, ru, en, kaa.
  TextColumn get language => text()();
  TextColumn get body => text()();
}

/// Журнал отправленных SMS (показывается в карточке должника).
@TableIndex(name: 'idx_sms_logs_debtor', columns: {#debtorId})
class SmsLogs extends Table with SyncColumns {
  TextColumn get debtorId => text().references(Debtors, #id)();
  TextColumn get phone => text()();
  TextColumn get body => text()();
  IntColumn get status => intEnum<SmsStatus>()();
  TextColumn get error => text().nullable()();
}
