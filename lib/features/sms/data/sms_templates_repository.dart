import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_columns.dart';
import '../domain/sms_template.dart';

/// Шаблоны: пользовательские правки хранятся в БД, по одной на язык;
/// без правки действует шаблон по умолчанию из кода.
class SmsTemplatesRepository {
  SmsTemplatesRepository(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$SmsTemplatesTable, SmsTemplate> get _active =>
      _db.select(_db.smsTemplates)..where((t) => t.deletedAt.isNull());

  /// Текст шаблона для [language] (правка пользователя или значение по умолчанию).
  Future<String> bodyFor(String language) async {
    final row = await (_active..where((t) => t.language.equals(language))).getSingleOrNull();
    return row?.body ?? defaultSmsTemplates[language] ?? defaultSmsTemplates['en']!;
  }

  /// Все четыре шаблона: язык → текст.
  Future<Map<String, String>> all() async {
    final rows = await _active.get();
    final custom = {for (final r in rows) r.language: r.body};
    return {for (final l in smsLanguages) l: custom[l] ?? defaultSmsTemplates[l]!};
  }

  Future<bool> isCustomized(String language) async =>
      await (_active..where((t) => t.language.equals(language))).getSingleOrNull() != null;

  /// Сохраняет правку. Текст, равный шаблону по умолчанию, снимает правку.
  Future<void> save(String language, String body) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError.value(body, 'body', 'Template must not be empty');
    if (text == defaultSmsTemplates[language]) return resetToDefault(language);

    final existing = await (_active..where((t) => t.language.equals(language))).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.smsTemplates).insert(
            SmsTemplatesCompanion.insert(language: language, body: text),
          );
    } else {
      await (_db.update(_db.smsTemplates)..where((t) => t.id.equals(existing.id))).write(
        SmsTemplatesCompanion(
          body: Value(text),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
    }
  }

  Future<void> resetToDefault(String language) {
    final now = DateTime.now();
    return (_db.update(_db.smsTemplates)
          ..where((t) => t.language.equals(language) & t.deletedAt.isNull()))
        .write(SmsTemplatesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      syncStatus: const Value(SyncStatus.pending),
    ));
  }
}
