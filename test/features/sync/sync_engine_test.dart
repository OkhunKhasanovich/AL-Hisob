import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/database/sync_columns.dart';
import 'package:al_hisob/core/domain/debt_direction.dart';
import 'package:al_hisob/core/domain/debt_kind.dart';
import 'package:al_hisob/core/domain/order_status.dart';
import 'package:al_hisob/core/domain/product_unit.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/core/domain/sms_status.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:al_hisob/features/debts/data/debtors_repository.dart';
import 'package:al_hisob/features/sync/data/sync_engine.dart';
import 'package:al_hisob/features/sync/domain/sync_api.dart';

import '../../helpers/fake_sync_api.dart';

/// Устройство: своя локальная база и свой движок, сервер общий.
class Device {
  Device(FakeSyncApi api, {this.userId = 'user-1'}) : db = AppDatabase(NativeDatabase.memory()) {
    engine = SyncEngine(db: db, api: api, batchSize: 3, pageSize: 2);
    debtors = DebtorsRepository(db);
  }

  final AppDatabase db;
  final String userId;
  late final SyncEngine engine;
  late final DebtorsRepository debtors;

  Future<SyncReport> sync() => engine.run(accessToken: 'token', userId: userId);

  Future<List<Debtor>> allDebtors() => db.select(db.debtors).get();
}

typedef TableInfoLike = Future<List<Map<String, Object?>>> Function(AppDatabase db);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeSyncApi server;
  late Device a;
  late Device b;

  setUp(() {
    server = FakeSyncApi();
    a = Device(server);
    b = Device(server);
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  test('local changes are pending until synced, then marked synced', () async {
    final id = await a.debtors.createDebtor(const DebtorInput(name: 'Alisher', phones: ['901234567'], initialDebt: 50000));
    expect(await a.engine.pendingCount(), greaterThan(0));

    final report = await a.sync();

    expect(report.pushed, greaterThan(0));
    expect(await a.engine.pendingCount(), 0);
    expect(server.find('debtors', id), isNotNull);
    expect(await a.engine.lastSyncedAt(), isNotNull);
  });

  test('data created on one device appears on another, including money operations', () async {
    final id = await a.debtors.createDebtor(const DebtorInput(name: 'Alisher', phones: ['901234567'], initialDebt: 50000));
    await a.debtors.addTransaction(
      debtorId: id,
      kind: DebtKind.payment,
      amount: 20000,
      occurredAt: DateTime(2026, 5, 1),
    );
    await a.sync();

    final report = await b.sync();

    expect(report.pulled, greaterThan(0));
    final summaries = await b.debtors.loadSummaries();
    expect(summaries.single.debtor.name, 'Alisher');
    expect(summaries.single.balance, 30000);
    // Принятое с сервера не должно снова уходить на сервер.
    expect(await b.engine.pendingCount(), 0);
    final pushesBefore = server.pushCalls;
    await b.sync();
    expect(server.pushCalls, pushesBefore);
  });

  test('a second sync with nothing new transfers nothing', () async {
    await a.debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    await a.sync();
    final again = await a.sync();
    expect(again.pushed, 0);
    expect(again.pulled, 0);
  });

  test('large sets are sent in batches and pulled across pages', () async {
    for (var i = 0; i < 7; i++) {
      await a.debtors.createDebtor(DebtorInput(name: 'D$i'));
    }
    await a.sync();
    expect(server.pushSizes.every((n) => n <= 3), isTrue);
    expect(server.pushCalls, greaterThanOrEqualTo(3));

    await b.sync();
    expect(await b.allDebtors(), hasLength(7));
  });

  test('the newest edit wins when two devices change the same record', () async {
    final id = await a.debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    await a.sync();
    await b.sync();

    await a.debtors.updateDebtor(id, const DebtorInput(name: 'Alisher A'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await b.debtors.updateDebtor(id, const DebtorInput(name: 'Alisher B'));

    await a.sync();
    await b.sync(); // B новее — побеждает
    await a.sync();

    expect((await a.allDebtors()).single.name, 'Alisher B');
    expect((await b.allDebtors()).single.name, 'Alisher B');
    expect(server.find('debtors', id)!.data['name'], 'Alisher B');
    expect(await a.engine.pendingCount(), 0);
    expect(await b.engine.pendingCount(), 0);
  });

  test('an older edit made offline does not overwrite a newer one on the server', () async {
    final id = await a.debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    await a.sync();
    await b.sync();

    await b.debtors.updateDebtor(id, const DebtorInput(name: 'Old edit'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await a.debtors.updateDebtor(id, const DebtorInput(name: 'New edit'));
    await a.sync();

    await b.sync(); // сервер отвечает «устарело» и отдаёт свежую версию

    expect((await b.allDebtors()).single.name, 'New edit');
    expect(await b.engine.pendingCount(), 0);
  });

  test('deleting travels as soft delete', () async {
    final id = await a.debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    await a.sync();
    await b.sync();

    await a.debtors.deleteDebtor(id);
    await a.sync();
    await b.sync();

    final row = (await b.allDebtors()).single;
    expect(row.deletedAt, isNotNull);
    expect(await b.debtors.loadSummaries(), isEmpty);
  });

  test('an edit made while the request is in flight is not marked synced and goes out next', () async {
    final id = await a.debtors.createDebtor(const DebtorInput(name: 'First'));
    final slow = _EditDuringPush(server, () => a.debtors.updateDebtor(id, const DebtorInput(name: 'Second')));
    final engine = SyncEngine(db: a.db, api: slow);

    await engine.run(accessToken: 't', userId: 'user-1');

    // Без защиты строка стала бы «отправленной» с устаревшим именем, а правка потерялась.
    expect(server.find('debtors', id)!.data['name'], 'Second');
    expect((await a.allDebtors()).single.name, 'Second');
    expect(await engine.pendingCount(), 0);
    expect(server.pushCalls, 2);
  });

  test('network failure keeps data pending and the next run recovers', () async {
    await a.debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    server.failNext = SyncApiException('network');

    await expectLater(a.sync(), throwsA(isA<SyncApiException>()));
    expect(await a.engine.pendingCount(), greaterThan(0));

    await a.sync();
    expect(await a.engine.pendingCount(), 0);
  });

  test('failed pull does not move the cursor, so nothing is lost', () async {
    for (var i = 0; i < 3; i++) {
      await a.debtors.createDebtor(DebtorInput(name: 'D$i'));
    }
    await a.sync();

    final failing = _FailPullOnce(server);
    final engine = SyncEngine(db: b.db, api: failing, pageSize: 1);
    await expectLater(engine.run(accessToken: 't', userId: 'user-1'), throwsA(isA<SyncApiException>()));
    expect(await b.allDebtors(), isEmpty);

    await engine.run(accessToken: 't', userId: 'user-1');
    expect(await b.allDebtors(), hasLength(3));
  });

  test('another account on the same device is refused', () async {
    await a.debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    await a.sync();

    await expectLater(
      a.engine.run(accessToken: 't', userId: 'user-2'),
      throwsA(isA<SyncAccountMismatch>()),
    );
  });

  test('records of unknown entities or broken shape are skipped, not fatal', () async {
    final good = await a.debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    await a.sync();
    await server.push('t', [
      SyncChange(entity: 'from_the_future', id: 'x', data: const {}, updatedAt: DateTime(2026)),
      SyncChange(entity: 'debtors', id: 'broken', data: const {'id': 'broken'}, updatedAt: DateTime(2026)),
    ]);

    final report = await b.sync();

    expect(report.skipped, 2);
    expect((await b.allDebtors()).map((d) => d.id), [good]);
  });

  test('все 11 таблиц проходят через настоящий JSON туда и обратно без потерь', () async {
    // Ловит то, что не видно на «чистых» объектах: значения, которые нельзя закодировать в JSON.
    final db = a.db;
    await ShopProfileRepository(db).create(name: 'Shop', roles: {ShopRole.wholesaler, ShopRole.buyer});
    final debtor = await a.debtors.createDebtor(const DebtorInput(name: 'Alisher', phones: ['901234567']));
    await a.debtors.addTransaction(
      debtorId: debtor,
      kind: DebtKind.debt,
      amount: 1000,
      occurredAt: DateTime(2026, 5, 1),
    );
    await db.into(db.smsTemplates).insert(SmsTemplatesCompanion.insert(language: 'ru', body: 'Hello {name}'));
    await db.into(db.smsLogs).insert(SmsLogsCompanion.insert(
          debtorId: debtor,
          phone: '+998901234567',
          body: 'Hello',
          status: SmsStatus.sent,
        ));
    final product = await db.into(db.products).insertReturning(ProductsCompanion.insert(
          name: 'Cola',
          unit: ProductUnit.piece,
          unitPrice: 12000,
          packKind: const Value(PackKind.box),
          packSize: const Value(24),
          packPrice: const Value(250000),
        ));
    await db.into(db.productPhotos).insert(
          ProductPhotosCompanion.insert(productId: product.id, fileName: 'a.jpg', position: 0),
        );
    final order = await db.into(db.orders).insertReturning(OrdersCompanion.insert(
          number: 1,
          customerId: debtor,
          status: OrderStatus.created,
          total: 24000,
        ));
    await db.into(db.orderItems).insert(OrderItemsCompanion.insert(
          orderId: order.id,
          name: 'Cola',
          unit: ProductUnit.piece,
          quantity: 2,
          unitPrice: 12000,
          lineTotal: 24000,
          position: 0,
        ));
    await db.into(db.orderStatusHistory).insert(OrderStatusHistoryCompanion.insert(
          orderId: order.id,
          status: OrderStatus.created,
          actorName: 'Shop',
        ));

    await a.sync();
    expect(await a.engine.pendingCount(), 0);
    expect(server.records.map((r) => r.entity).toSet(), hasLength(11), reason: 'на сервер ушли все таблицы');

    await b.sync();

    Future<List<Map<String, Object?>>> rows(AppDatabase d, TableInfoLike t) => t(d);
    final tables = <TableInfoLike>[
      (d) async => [for (final r in await d.select(d.shopProfiles).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.debtors).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.debtorPhones).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.debtTransactions).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.smsTemplates).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.smsLogs).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.products).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.productPhotos).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.orders).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.orderItems).get()) r.toJson().cast()],
      (d) async => [for (final r in await d.select(d.orderStatusHistory).get()) r.toJson().cast()],
    ];
    for (final t in tables) {
      final fromA = await rows(a.db, t);
      final fromB = await rows(b.db, t);
      expect(fromA, hasLength(1));
      expect(fromB, hasLength(1));
      // Совпадает всё, кроме отметки синхронизации (на B запись уже «совпадает с сервером»).
      expect({...fromB.single}..remove('syncStatus'), {...fromA.single}..remove('syncStatus'));
    }
    final profile = await ShopProfileRepository(b.db).current();
    expect(profile!.roles, {ShopRole.wholesaler, ShopRole.buyer}, reason: 'роли набором дошли целыми');
  });

  test('должник от старой версии приложения (без поля direction) принимается как «мне должны»', () async {
    final id = '11111111-1111-4111-8111-111111111111';
    await server.push('t', [
      SyncChange(
        entity: 'debtors',
        id: id,
        updatedAt: DateTime(2026, 5, 1),
        // Как отправила бы версия до появления «Я должен»: полей direction нет.
        data: {
          'id': id,
          'createdAt': DateTime(2026, 5, 1).millisecondsSinceEpoch,
          'updatedAt': DateTime(2026, 5, 1).millisecondsSinceEpoch,
          'deletedAt': null,
          'syncStatus': 1,
          'name': 'Old app debtor',
          'shopName': null,
          'address': null,
          'note': null,
        },
      ),
    ]);

    final report = await b.sync();

    expect(report.skipped, 0);
    final row = (await b.allDebtors()).single;
    expect(row.name, 'Old app debtor');
    expect(row.direction, DebtDirection.receivable);
  });

  test('pulled rows are stored as synced', () async {
    await a.debtors.createDebtor(const DebtorInput(name: 'Alisher'));
    await a.sync();
    await b.sync();
    expect((await b.allDebtors()).single.syncStatus, SyncStatus.synced);
  });
}

/// Делает правку, пока «запрос идёт» (после снимка строк, до ответа сервера).
class _EditDuringPush implements SyncApi {
  _EditDuringPush(this._inner, this._edit);

  final FakeSyncApi _inner;
  final Future<void> Function() _edit;
  bool _done = false;

  @override
  Future<PushResult> push(String accessToken, List<SyncChange> changes) async {
    final result = await _inner.push(accessToken, changes);
    if (!_done) {
      _done = true;
      await _edit();
    }
    return result;
  }

  @override
  Future<PullPage> pull(String accessToken, {required int since, int limit = 500}) =>
      _inner.pull(accessToken, since: since, limit: limit);
}

/// Первая страница приходит, вторая — обрыв связи.
class _FailPullOnce implements SyncApi {
  _FailPullOnce(this._inner);

  final FakeSyncApi _inner;
  var _calls = 0;

  @override
  Future<PushResult> push(String accessToken, List<SyncChange> changes) => _inner.push(accessToken, changes);

  @override
  Future<PullPage> pull(String accessToken, {required int since, int limit = 500}) {
    if (++_calls == 2) throw SyncApiException('network');
    return _inner.pull(accessToken, since: since, limit: limit);
  }
}
