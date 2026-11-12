import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_providers.dart';
import '../domain/sync_api.dart';
import 'http_sync_api.dart';
import 'sync_engine.dart';

/// Переопределяется в тестах.
final syncApiProvider = Provider<SyncApi>((ref) => HttpSyncApi());

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(db: ref.watch(appDatabaseProvider), api: ref.watch(syncApiProvider)),
);

/// Интервалы фоновой синхронизации. В тестах заменяются на короткие.
class SyncTiming {
  const SyncTiming({
    this.debounce = const Duration(seconds: 3),
    this.interval = const Duration(minutes: 5),
    this.retryBase = const Duration(seconds: 30),
    this.retryMax = const Duration(minutes: 10),
  });

  /// Пауза после последней правки: серия правок уходит одной отправкой.
  final Duration debounce;

  /// Как часто проверять сервер, пока приложение открыто.
  final Duration interval;

  /// Первая пауза после неудачи; дальше удваивается до [retryMax].
  final Duration retryBase;
  final Duration retryMax;

  Duration retryAfter(int failures) {
    var d = retryBase;
    for (var i = 1; i < failures && d < retryMax; i++) {
      d *= 2;
    }
    return d > retryMax ? retryMax : d;
  }
}

final syncTimingProvider = Provider<SyncTiming>((ref) => const SyncTiming());
