import 'dart:async';

import 'package:drift/drift.dart';

import 'app_database.dart';

/// Выдаёт результат [load] сразу и после каждого изменения [tables].
///
/// Не `async*`: у генератора `cancel()` не срабатывает, пока он ждёт событие,
/// и подписка висела бы после ухода с экрана. Результаты устаревших загрузок
/// отбрасываются, чтобы порядок событий не нарушался.
Stream<T> watchTables<T>(
  AppDatabase db,
  List<TableInfo<Table, Object?>> tables,
  Future<T> Function() load,
) {
  late final StreamController<T> controller;
  StreamSubscription<Set<TableUpdate>>? changes;
  var generation = 0;

  Future<void> emit() async {
    final mine = ++generation;
    try {
      final value = await load();
      if (mine == generation && !controller.isClosed) controller.add(value);
    } catch (e, st) {
      if (mine == generation && !controller.isClosed) controller.addError(e, st);
    }
  }

  controller = StreamController<T>(
    onListen: () {
      changes = db.tableUpdates(TableUpdateQuery.onAllTables(tables)).listen((_) => emit());
      emit();
    },
    onCancel: () async {
      await changes?.cancel();
      await controller.close();
    },
  );
  return controller.stream;
}
