import '../../../core/database/app_database.dart';
import '../domain/sync_api.dart';
import 'sync_entities.dart';

/// Чужой аккаунт: на устройстве данные другого пользователя. Отправлять их в этот
/// аккаунт нельзя, поэтому синхронизация не запускается.
class SyncAccountMismatch implements Exception {
  @override
  String toString() => 'SyncAccountMismatch';
}

class SyncReport {
  const SyncReport({this.pushed = 0, this.pulled = 0, this.skipped = 0});

  final int pushed;
  final int pulled;

  /// Пришедшие записи, которые не удалось разобрать (например, от более новой версии приложения).
  final int skipped;
}

/// Один цикл синхронизации: отправить локальные изменения, затем забрать чужие.
///
/// Приложение пишет только в локальную базу, а движок запускается отдельно и
/// ничего не блокирует: экраны читают ту же базу и обновляются сами.
/// Конфликты решает «побеждает самая свежая правка» (по `updatedAt`).
class SyncEngine {
  SyncEngine({required this.db, required this.api, this.batchSize = 200, this.pageSize = 500})
      : _entities = buildSyncEntities(db);

  final AppDatabase db;
  final SyncApi api;
  final int batchSize;
  final int pageSize;
  final List<SyncEntity> _entities;

  static const _userKey = 'sync.user';
  static const _cursorKey = 'sync.cursor';
  static const _lastSyncKey = 'sync.last_at';

  /// Сколько записей ждёт отправки.
  Future<int> pendingCount() async {
    var total = 0;
    for (final e in _entities) {
      total += await e.pendingCount();
    }
    return total;
  }

  Future<DateTime?> lastSyncedAt() async {
    final raw = await _getSetting(_lastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<SyncReport> run({required String accessToken, required String userId}) async {
    final owner = await _getSetting(_userKey);
    if (owner != null && owner != userId) throw SyncAccountMismatch();
    if (owner == null) await _setSetting(_userKey, userId);

    final pushed = await _push(accessToken);
    final (pulled, skipped) = await _pull(accessToken);
    await _setSetting(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
    return SyncReport(pushed: pushed, pulled: pulled, skipped: skipped);
  }

  // ---------- отправка ----------

  Future<int> _push(String accessToken) async {
    var total = 0;
    // Страховка от бесконечного цикла: за один запуск не больше 100 пачек.
    for (var i = 0; i < 100; i++) {
      final batch = <(SyncEntity, Map<String, Object?>)>[];
      for (final e in _entities) {
        if (batch.length >= batchSize) break;
        for (final row in await e.pending(batchSize - batch.length)) {
          batch.add((e, row));
        }
      }
      if (batch.isEmpty) return total;

      final changes = [for (final (e, row) in batch) _toChange(e, row)];
      final result = await api.push(accessToken, changes);

      var progressed = false;
      for (final (e, row) in batch) {
        if (result.accepted.contains(row['id'])) {
          await e.markSyncedIfUnchanged(row['id']! as String, row);
          progressed = true;
          total++;
        }
      }
      if (result.stale.isNotEmpty) {
        // На сервере версия новее (или такая же по времени, но другая): принимаем серверную.
        await _apply(result.stale, serverWinsTies: true);
        progressed = true;
      }
      if (!progressed) return total;
    }
    return total;
  }

  SyncChange _toChange(SyncEntity e, Map<String, Object?> row) => SyncChange(
        entity: e.name,
        id: row['id']! as String,
        data: row,
        updatedAt: _time(row['updatedAt'])!,
        deletedAt: _time(row['deletedAt']),
      );

  // ---------- получение ----------

  Future<(int, int)> _pull(String accessToken) async {
    var cursor = int.tryParse(await _getSetting(_cursorKey) ?? '') ?? 0;
    final all = <SyncChange>[];
    // Сначала забираем всё, потом применяем одной транзакцией: курсор сдвигается
    // только вместе с данными, обрыв связи посреди загрузки ничего не ломает.
    for (var i = 0; i < 200; i++) {
      final page = await api.pull(accessToken, since: cursor, limit: pageSize);
      all.addAll(page.changes);
      cursor = page.cursor;
      if (!page.hasMore) break;
    }
    final skipped = await _apply(all, newCursor: cursor);
    return (all.length - skipped, skipped);
  }

  /// Применяет записи с сервера. Своя правка новее — остаётся (уйдёт при отправке).
  /// Возвращает число пропущенных записей.
  Future<int> _apply(List<SyncChange> changes, {int? newCursor, bool serverWinsTies = false}) async {
    final byName = {for (final e in _entities) e.name: e};
    var skipped = 0;
    // Порядок сервера может не совпасть с порядком зависимостей; внешние ключи на время
    // применения отключаем: «сирота» дождётся родителя в следующей пачке.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction(() async {
        for (final c in changes) {
          final entity = byName[c.entity];
          if (entity == null) {
            skipped++;
            continue;
          }
          final local = await entity.byId(c.id);
          if (local != null) {
            final localTime = _time(local['updatedAt'])!;
            final incoming = c.updatedAt;
            final newer = serverWinsTies ? !incoming.isBefore(localTime) : incoming.isAfter(localTime);
            if (!newer) continue;
          }
          try {
            await entity.upsertSynced(c.data);
          } on Object {
            skipped++;
          }
        }
        if (newCursor != null) await _setSetting(_cursorKey, '$newCursor');
      });
    } finally {
      await db.customStatement('PRAGMA foreign_keys = ON');
    }
    return skipped;
  }

  // ---------- служебное ----------

  /// Время из JSON строки (миллисекунды с эпохи).
  static DateTime? _time(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  Future<String?> _getSetting(String key) async {
    final row = await (db.select(db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setSetting(String key, String value) => db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );
}
