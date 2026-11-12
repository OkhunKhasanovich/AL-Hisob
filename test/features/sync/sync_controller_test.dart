import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/features/auth/data/auth_providers.dart';
import 'package:al_hisob/features/auth/presentation/auth_controller.dart';
import 'package:al_hisob/features/auth/presentation/login_prompt.dart';
import 'package:al_hisob/features/debts/data/debtors_repository.dart';
import 'package:al_hisob/features/sync/data/sync_providers.dart';
import 'package:al_hisob/features/sync/domain/sync_api.dart';
import 'package:al_hisob/features/sync/presentation/sync_controller.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_sync_api.dart';

const _fast = SyncTiming(
  debounce: Duration(milliseconds: 40),
  interval: Duration(hours: 1),
  retryBase: Duration(milliseconds: 80),
  retryMax: Duration(milliseconds: 200),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeSyncApi api;
  late InMemoryTokenStore tokens;
  late ProviderContainer container;

  ProviderContainer make({bool signedIn = true, bool server = true, SyncApi? withApi}) {
    tokens = InMemoryTokenStore(signedIn ? fakeSession() : null);
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      syncApiProvider.overrideWithValue(withApi ?? api),
      syncTimingProvider.overrideWithValue(_fast),
      tokenStoreProvider.overrideWithValue(tokens),
      serverConfiguredProvider.overrideWithValue(server),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Ждёт условия, не блокируя тест надолго.
  Future<void> until(bool Function() cond, {Duration limit = const Duration(seconds: 5)}) async {
    final end = DateTime.now().add(limit);
    while (!cond()) {
      if (DateTime.now().isAfter(end)) fail('timeout waiting for condition');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeSyncApi();
  });
  tearDown(() => db.close());

  test('writes are visible immediately, and reach the server in the background', () async {
    container = make();
    await container.read(authControllerProvider.future);
    container.listen(syncControllerProvider, (_, _) {});
    final debtors = DebtorsRepository(db);

    final id = await debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    // Локальная запись видна сразу, сервер ещё мог не получить её: приложение не ждёт.
    expect(await debtors.loadSummaries(), hasLength(1));

    await until(() => api.find('debtors', id) != null);
    await until(() => container.read(syncControllerProvider).phase == SyncPhase.idle);
    expect(container.read(syncControllerProvider).pending, 0);
  });

  test('a slow server does not delay local reads and writes', () async {
    final slow = _SlowApi(api);
    container = make(withApi: slow);
    await container.read(authControllerProvider.future);
    container.listen(syncControllerProvider, (_, _) {});
    final debtors = DebtorsRepository(db);
    await until(() => slow.started); // синхронизация «зависла» на сервере

    final watch = Stopwatch()..start();
    await debtors.createDebtor(const DebtorInput(name: 'During sync'));
    final list = await debtors.loadSummaries();
    watch.stop();

    expect(list, hasLength(1));
    expect(watch.elapsedMilliseconds, lessThan(1000));
    expect(container.read(syncControllerProvider).phase, SyncPhase.syncing);
    slow.release();
  });

  test('offline: data stays local, status shows offline, then it recovers by itself', () async {
    container = make();
    await container.read(authControllerProvider.future);
    api.failNext = SyncApiException('network');
    container.listen(syncControllerProvider, (_, _) {});
    final debtors = DebtorsRepository(db);
    final id = await debtors.createDebtor(const DebtorInput(name: 'Alisher'));

    await until(() => container.read(syncControllerProvider).phase == SyncPhase.offline);
    expect(container.read(syncControllerProvider).pending, greaterThan(0));
    expect(await debtors.loadSummaries(), hasLength(1));

    await until(() => api.find('debtors', id) != null); // повтор после паузы
    await until(() => container.read(syncControllerProvider).phase == SyncPhase.idle);
  });

  test('not signed in: nothing is sent and the state stays off', () async {
    container = make(signedIn: false);
    await container.read(authControllerProvider.future);
    container.listen(syncControllerProvider, (_, _) {});
    await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Alisher'));

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(api.pushCalls, 0);
    expect(container.read(syncControllerProvider).phase, SyncPhase.off);
  });

  test('server not configured: nothing is sent', () async {
    container = make(server: false);
    await container.read(authControllerProvider.future);
    container.listen(syncControllerProvider, (_, _) {});
    await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Alisher'));

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(api.pushCalls, 0);
  });

  test('signing in starts the first sync of what was entered before', () async {
    container = make(signedIn: false);
    await container.read(authControllerProvider.future);
    container.listen(syncControllerProvider, (_, _) {});
    final id = await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'From notebook'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(api.find('debtors', id), isNull);

    await container.read(authControllerProvider.notifier).signIn(fakeSession());

    await until(() => api.find('debtors', id) != null);
  });

  test('signing out stops synchronization but keeps the data', () async {
    container = make();
    await container.read(authControllerProvider.future);
    container.listen(syncControllerProvider, (_, _) {});
    await until(() => container.read(syncControllerProvider).phase == SyncPhase.idle);

    await container.read(authControllerProvider.notifier).signOut();
    final calls = api.pushCalls;
    await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'After sign out'));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(container.read(syncControllerProvider).phase, SyncPhase.off);
    expect(api.pushCalls, calls);
    expect(await DebtorsRepository(db).loadSummaries(), hasLength(1));
  });

  test('unexpected errors never escape the controller', () async {
    container = make(withApi: _BrokenApi());
    await container.read(authControllerProvider.future);
    container.listen(syncControllerProvider, (_, _) {});
    await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Alisher'));

    await until(() => container.read(syncControllerProvider).phase == SyncPhase.error);
  });
}

/// Сервер, который отвечает только после [release].
class _SlowApi implements SyncApi {
  _SlowApi(this._inner);

  final FakeSyncApi _inner;
  bool started = false;
  bool _released = false;

  void release() => _released = true;

  @override
  Future<PushResult> push(String accessToken, List<SyncChange> changes) async {
    started = true;
    while (!_released) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return _inner.push(accessToken, changes);
  }

  @override
  Future<PullPage> pull(String accessToken, {required int since, int limit = 500}) async {
    started = true;
    while (!_released) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return _inner.pull(accessToken, since: since, limit: limit);
  }
}

class _BrokenApi implements SyncApi {
  @override
  Future<PushResult> push(String accessToken, List<SyncChange> changes) async => throw StateError('boom');

  @override
  Future<PullPage> pull(String accessToken, {required int since, int limit = 500}) async =>
      throw StateError('boom');
}
