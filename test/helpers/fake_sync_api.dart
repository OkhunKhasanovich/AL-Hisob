import 'dart:convert';

import 'package:al_hisob/features/sync/domain/sync_api.dart';

/// Сервер синхронизации в памяти с теми же правилами, что и настоящий:
/// побеждает более свежая правка, равные по времени и разные по данным — версия сервера.
class FakeSyncApi implements SyncApi {
  final Map<String, SyncChange> _records = {};
  int _seq = 0;

  /// Ошибка, которую выбросит следующий запрос (и сбросится).
  SyncApiException? failNext;

  int pushCalls = 0;
  int pullCalls = 0;
  final List<int> pushSizes = [];

  Iterable<SyncChange> get records => _records.values;

  SyncChange? find(String entity, String id) => _records['$entity/$id'];

  void _maybeFail() {
    final e = failNext;
    if (e != null) {
      failNext = null;
      throw e;
    }
  }

  @override
  Future<PushResult> push(String accessToken, List<SyncChange> changes) async {
    pushCalls++;
    pushSizes.add(changes.length);
    _maybeFail();
    final accepted = <String>{};
    final stale = <SyncChange>[];
    for (final sent in changes) {
      // Как по сети: запись проходит через настоящий JSON. Так ловятся значения,
      // которые не кодируются (например, `Set` из конвертера), а на «сервере» их не видно.
      final c = _wire(sent);
      final key = '${c.entity}/${c.id}';
      final current = _records[key];
      if (current == null || c.updatedAt.isAfter(current.updatedAt)) {
        _records[key] = _stored(c);
        accepted.add(c.id);
      } else if (c.updatedAt == current.updatedAt && _sameData(c.data, current.data)) {
        accepted.add(c.id);
      } else {
        stale.add(current);
      }
    }
    return PushResult(accepted: accepted, stale: stale);
  }

  @override
  Future<PullPage> pull(String accessToken, {required int since, int limit = 500}) async {
    pullCalls++;
    _maybeFail();
    final newer = _records.values.where((r) => r.seq! > since).toList()..sort((a, b) => a.seq!.compareTo(b.seq!));
    final page = newer.take(limit).toList();
    return PullPage(
      changes: page,
      cursor: page.isEmpty ? since : page.last.seq!,
      hasMore: newer.length > limit,
    );
  }

  static SyncChange _wire(SyncChange c) =>
      SyncChange.fromJson((jsonDecode(jsonEncode(c.toJson())) as Map).cast<String, Object?>());

  SyncChange _stored(SyncChange c) => SyncChange(
        entity: c.entity,
        id: c.id,
        data: c.data,
        updatedAt: c.updatedAt,
        deletedAt: c.deletedAt,
        seq: ++_seq,
      );

  static bool _sameData(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length && a.keys.every((k) => a[k] == b[k]);
}
