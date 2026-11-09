import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/settings/settings_providers.dart';
import 'shop_profile_repository.dart';

final shopProfileRepositoryProvider = Provider<ShopProfileRepository>(
  (ref) => ShopProfileRepository(ref.watch(appDatabaseProvider)),
);

/// Текущий профиль; `null` — онбординг ещё не пройден.
final shopProfileProvider = StreamProvider<ShopProfile?>(
  (ref) => ref.watch(shopProfileRepositoryProvider).watch(),
);
