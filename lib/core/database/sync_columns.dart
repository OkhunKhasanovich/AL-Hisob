import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Новый UUID v4 для `id`. Отдельная функция, потому что drift копирует
/// выражение `clientDefault` в сгенерированный код, где нет импорта `uuid`.
String generateId() => _uuid.v4();

/// Статус синхронизации записи с сервером (этап 9).
enum SyncStatus {
  /// Изменена локально, ещё не отправлена.
  pending,

  /// Совпадает с сервером.
  synced,

  /// Конфликт зафиксирован в журнале, ждёт разбора.
  conflict,
}

/// Общие колонки для всех синхронизируемых таблиц (должники, операции,
/// заказы, каталог и т.д.). Подключается как `with SyncColumns`.
///
/// * `id` — UUID v4, генерируется на клиенте, поэтому записи можно создавать
///   офлайн и без аккаунта.
/// * `deletedAt` — soft delete: запись не удаляется физически, чтобы удаление
///   дошло до сервера.
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(generateId)();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get syncStatus => intEnum<SyncStatus>()
      .withDefault(Constant(SyncStatus.pending.index))();

  @override
  Set<Column> get primaryKey => {id};
}
