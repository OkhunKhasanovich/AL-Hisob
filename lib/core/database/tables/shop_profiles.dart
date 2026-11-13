import 'package:drift/drift.dart';

import '../../domain/shop_role.dart';
import '../sync_columns.dart';

/// Роли в БД: имена через запятую («wholesaler,buyer»).
///
/// `JsonTypeConverter`: в JSON (для синхронизации) роли идут той же строкой, что и в БД.
/// Без него `toJson()` отдавал бы `Set`, который не кодируется в JSON, и синхронизация падала.
class ShopRolesConverter extends TypeConverter<Set<ShopRole>, String>
    with JsonTypeConverter<Set<ShopRole>, String> {
  const ShopRolesConverter();

  @override
  Set<ShopRole> fromSql(String fromDb) => {
        for (final name in fromDb.split(','))
          for (final role in ShopRole.values)
            if (role.name == name) role,
      };

  @override
  String toSql(Set<ShopRole> value) => (value.toList()
        ..sort((a, b) => a.index.compareTo(b.index)))
      .map((r) => r.name)
      .join(',');
}

/// Профиль магазина/фирмы владельца приложения. Одна активная запись.
class ShopProfiles extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get roles => text().map(const ShopRolesConverter())();
}
