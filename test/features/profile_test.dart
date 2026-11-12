import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/database/sync_columns.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/features/profile/shop_name_validator.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';

void main() {
  group('валидация названия', () {
    test('нормализация пробелов', () {
      expect(normalizeShopName('  Baraka   Trade '), 'Baraka Trade');
    });

    test('границы длины', () {
      expect(isValidShopName(''), isFalse);
      expect(isValidShopName(' a '), isFalse);
      expect(isValidShopName('ab'), isTrue);
      expect(isValidShopName('a' * 60), isTrue);
      expect(isValidShopName('a' * 61), isFalse);
    });
  });

  group('ShopProfileRepository', () {
    late AppDatabase db;
    late ShopProfileRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = ShopProfileRepository(db);
    });
    tearDown(() => db.close());

    test('профиля нет до онбординга', () async {
      expect(await repo.current(), isNull);
    });

    test('create заполняет служебные поля', () async {
      final profile = await repo.create(
        name: '  Baraka   Trade ',
        roles: {ShopRole.wholesaler},
      );

      expect(profile.id, hasLength(36));
      expect(profile.name, 'Baraka Trade');
      expect(profile.roles, {ShopRole.wholesaler});
      expect(profile.syncStatus, SyncStatus.pending);
      expect(profile.deletedAt, isNull);
      expect((await repo.current())?.id, profile.id);
    });

    test('роли хранятся набором и читаются обратно', () async {
      await repo.create(name: 'Shop', roles: {ShopRole.buyer, ShopRole.wholesaler});
      expect((await repo.current())!.roles, {ShopRole.wholesaler, ShopRole.buyer});
    });

    test('update меняет данные и помечает запись на синхронизацию', () async {
      final created = await repo.create(name: 'Old name', roles: {ShopRole.buyer});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.update(id: created.id, name: 'New name', roles: {ShopRole.wholesaler});

      final updated = (await repo.current())!;
      expect(updated.name, 'New name');
      expect(updated.roles, {ShopRole.wholesaler});
      expect(updated.updatedAt.isAfter(created.updatedAt), isTrue);
      expect(updated.createdAt, created.createdAt);
    });

    test('soft delete скрывает профиль', () async {
      final created = await repo.create(name: 'Shop', roles: {ShopRole.buyer});
      await (db.update(db.shopProfiles)..where((t) => t.id.equals(created.id)))
          .write(ShopProfilesCompanion(deletedAt: Value(DateTime.now())));
      expect(await repo.current(), isNull);
    });

    test('невалидные данные отклоняются', () {
      expect(() => repo.create(name: 'x', roles: {ShopRole.buyer}), throwsArgumentError);
      expect(() => repo.create(name: 'Shop', roles: {}), throwsArgumentError);
    });

    test('watch сообщает о создании профиля', () async {
      final events = repo.watch();
      final expectation = expectLater(
        events,
        emitsInOrder([isNull, isA<ShopProfile>()]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await repo.create(name: 'Shop', roles: {ShopRole.buyer});
      await expectation;
    });
  });
}
