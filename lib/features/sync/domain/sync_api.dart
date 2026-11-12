/// Запись, которой обмениваются приложение и сервер. Сервер хранит [data] как есть
/// (JSON строки локальной таблицы), поэтому изменения схемы приложения не требуют
/// правок на сервере.
class SyncChange {
  const SyncChange({
    required this.entity,
    required this.id,
    required this.data,
    required this.updatedAt,
    this.deletedAt,
    this.seq,
  });

  factory SyncChange.fromJson(Map<String, Object?> json) => SyncChange(
        entity: json['entity']! as String,
        id: json['id']! as String,
        data: (json['data']! as Map).cast<String, Object?>(),
        updatedAt: DateTime.parse(json['updated_at']! as String),
        deletedAt: json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at']! as String),
        seq: json['seq'] as int?,
      );

  final String entity;
  final String id;
  final Map<String, Object?> data;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Порядковый номер на сервере (только у полученных записей).
  final int? seq;

  Map<String, Object?> toJson() => {
        'entity': entity,
        'id': id,
        'data': data,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };
}

class PushResult {
  const PushResult({required this.accepted, required this.stale});

  /// Сохранены на сервере (или уже были там в таком же виде).
  final Set<String> accepted;

  /// На сервере версия новее — вот она.
  final List<SyncChange> stale;
}

class PullPage {
  const PullPage({required this.changes, required this.cursor, required this.hasMore});

  final List<SyncChange> changes;
  final int cursor;
  final bool hasMore;
}

class SyncApiException implements Exception {
  SyncApiException(this.code, {this.status = 0});

  final String code;

  /// 0 — сервер недоступен (нет сети, таймаут).
  final int status;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'SyncApiException($code, $status)';
}

abstract interface class SyncApi {
  Future<PushResult> push(String accessToken, List<SyncChange> changes);

  Future<PullPage> pull(String accessToken, {required int since, int limit = 500});
}
