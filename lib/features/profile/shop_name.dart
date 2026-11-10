import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import 'profile_providers.dart';

/// Название вашего магазина (из профиля). Вызывать из `build`: подписка нужна,
/// иначе поток профиля ещё не отдал значение и подставится запасное.
String watchShopName(WidgetRef ref, BuildContext context) =>
    ref.watch(shopProfileProvider).value?.name ?? context.l10n.appName;

/// То же в обработчиках событий (подписка уже создана через [watchShopName]).
String readShopName(WidgetRef ref, BuildContext context) =>
    ref.read(shopProfileProvider).value?.name ?? context.l10n.appName;
