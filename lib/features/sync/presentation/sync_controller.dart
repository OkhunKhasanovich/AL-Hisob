import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/login_prompt.dart' show serverConfiguredProvider;
import '../data/sync_engine.dart';
import '../data/sync_providers.dart';
import '../domain/sync_api.dart';

enum SyncPhase {
  /// Не вошли или сервера нет — синхронизации нет, всё работает локально.
  off,
  idle,
  syncing,

  /// Нет связи: данные на телефоне, отправятся позже.
  offline,
  error,

  /// На телефоне данные другого аккаунта.
  accountMismatch,
}

class SyncState {
  const SyncState({this.phase = SyncPhase.off, this.pending = 0, this.lastSyncedAt, this.detail});

  final SyncPhase phase;

  /// Короткая техническая причина последнего сбоя (`HTTP 404 · not_found`, `network`…).
  /// Показывается мелким текстом, чтобы по скриншоту было понятно, что не так.
  final String? detail;

  /// Сколько записей ждёт отправки.
  final int pending;
  final DateTime? lastSyncedAt;

  SyncState copyWith({SyncPhase? phase, int? pending, DateTime? lastSyncedAt, String? detail}) =>
      SyncState(
        phase: phase ?? this.phase,
        pending: pending ?? this.pending,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        detail: detail,
      );
}

/// Фоновая синхронизация. Экраны и репозитории про неё не знают: они пишут в
/// локальную базу и сразу видят результат. Здесь только решаем, когда запускать
/// цикл: после правок (с паузой), при входе, при возврате в приложение и по таймеру.
/// Любая ошибка остаётся внутри — интерфейс не блокируется и не падает.
class SyncController extends Notifier<SyncState> {
  Timer? _debounce;
  Timer? _periodic;
  Timer? _retry;
  StreamSubscription<Object?>? _dbSub;
  AppLifecycleListener? _lifecycle;
  bool _running = false;
  Future<void>? _current;
  bool _again = false;
  int _failures = 0;

  @override
  SyncState build() {
    ref.listen(authControllerProvider, (previous, next) {
      final was = previous?.value?.user.id;
      final now = next.value?.user.id;
      if (now == was) return;
      if (now == null) {
        _stop();
        state = const SyncState();
      } else {
        _start();
      }
    });
    ref.onDispose(_stop);

    if (ref.read(authControllerProvider).value != null) {
      // Старт приложения со входом: запуск после первого кадра, не мешая открытию.
      scheduleMicrotask(_start);
    }
    return const SyncState();
  }

  bool get _enabled => ref.read(serverConfiguredProvider) && ref.read(authControllerProvider).value != null;

  void _start() {
    if (!ref.mounted || !_enabled) return;
    final timing = ref.read(syncTimingProvider);
    _stop();
    state = state.copyWith(phase: SyncPhase.idle);
    _dbSub = ref.read(appDatabaseProvider).tableUpdates().listen((updates) {
      // Служебные настройки (курсор и т.п.) не данные пользователя.
      if (_running || updates.every((u) => u.table == 'app_settings')) return;
      _debounce?.cancel();
      _debounce = Timer(timing.debounce, _kick);
    });
    _periodic = Timer.periodic(timing.interval, (_) => _kick());
    _lifecycle = AppLifecycleListener(onResume: _kick);
    _kick();
  }

  void _stop() {
    _debounce?.cancel();
    _periodic?.cancel();
    _retry?.cancel();
    _dbSub?.cancel();
    _lifecycle?.dispose();
    _debounce = _periodic = _retry = null;
    _dbSub = null;
    _lifecycle = null;
    _failures = 0;
    _again = false;
  }

  /// Запустить цикл «когда получится», не дожидаясь результата.
  void _kick() {
    unawaited(syncNow());
  }

  /// Синхронизировать сейчас (кнопка). Не бросает исключений. Если цикл уже идёт, новый не
  /// запускается, а возвращается тот же: вызывающий дожидается его окончания.
  Future<void> syncNow() {
    if (!ref.mounted || !_enabled) return Future.value();
    final running = _current;
    if (running != null) {
      _again = true;
      return running;
    }
    return _current = _runCycle().whenComplete(() => _current = null);
  }

  Future<void> _runCycle() async {
    _running = true;
    _retry?.cancel();
    final engine = ref.read(syncEngineProvider);
    state = state.copyWith(phase: SyncPhase.syncing);
    var ok = false;
    try {
      final auth = ref.read(authControllerProvider.notifier);
      final token = await auth.validAccessToken();
      if (!ref.mounted) return;
      final user = ref.read(authControllerProvider).value?.user;
      if (token == null || user == null) {
        state = const SyncState();
        return;
      }
      await engine.run(accessToken: token, userId: user.id);
      final pending = await engine.pendingCount();
      final last = await engine.lastSyncedAt();
      if (!ref.mounted) return;
      _failures = 0;
      ok = true;
      state = SyncState(phase: SyncPhase.idle, pending: pending, lastSyncedAt: last);
    } on SyncAccountMismatch {
      if (ref.mounted) state = state.copyWith(phase: SyncPhase.accountMismatch);
    } on SyncApiException catch (e) {
      await _failed(
        engine,
        e.isNetwork ? SyncPhase.offline : SyncPhase.error,
        e.isNetwork ? 'network' : 'HTTP ${e.status} · ${e.code}',
      );
    } on Object catch (e) {
      await _failed(engine, SyncPhase.error, '${e.runtimeType}');
    } finally {
      _running = false;
    }
    if (ref.mounted && ok && (_again || state.pending > 0)) {
      // Пока шёл цикл, появились новые правки.
      _again = false;
      _debounce?.cancel();
      _debounce = Timer(ref.read(syncTimingProvider).debounce, _kick);
    }
  }

  Future<void> _failed(SyncEngine engine, SyncPhase phase, String detail) async {
    if (!ref.mounted) return;
    _failures++;
    int pending = state.pending;
    try {
      pending = await engine.pendingCount();
    } on Object {
      // оставляем прежнее число
    }
    if (!ref.mounted) return;
    state = state.copyWith(phase: phase, pending: pending, detail: detail);
    _retry?.cancel();
    _retry = Timer(ref.read(syncTimingProvider).retryAfter(_failures), _kick);
  }
}


final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
