import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/domain/shop_role.dart';
import 'shop_name_validator.dart';

class ShopProfileRepository {
  ShopProfileRepository(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$ShopProfilesTable, ShopProfile> get _activeProfile =>
      _db.select(_db.shopProfiles)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
        ..limit(1);

  Future<ShopProfile?> current() => _activeProfile.getSingleOrNull();

  Stream<ShopProfile?> watch() => _activeProfile.watchSingleOrNull();

  /// Создаёт профиль при первом запуске.
  Future<ShopProfile> create({required String name, required Set<ShopRole> roles}) {
    _check(name, roles);
    return _db.into(_db.shopProfiles).insertReturning(
          ShopProfilesCompanion.insert(
            name: normalizeShopName(name),
            roles: roles,
          ),
        );
  }

  /// Меняет название и роли существующего профиля.
  Future<void> update({
    required String id,
    required String name,
    required Set<ShopRole> roles,
  }) async {
    _check(name, roles);
    await (_db.update(_db.shopProfiles)..where((t) => t.id.equals(id))).write(
      ShopProfilesCompanion(
        name: Value(normalizeShopName(name)),
        roles: Value(roles),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
  }

  void _check(String name, Set<ShopRole> roles) {
    if (!isValidShopName(name)) {
      throw ArgumentError.value(name, 'name', 'Invalid shop name');
    }
    if (roles.isEmpty) {
      throw ArgumentError.value(roles, 'roles', 'At least one role is required');
    }
  }
}
