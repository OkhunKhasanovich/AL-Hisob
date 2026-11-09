import 'package:flutter/material.dart';

import '../../core/domain/shop_role.dart';
import '../../core/l10n/l10n.dart';

extension ShopRoleL10n on ShopRole {
  String label(AppLocalizations l10n) => switch (this) {
        ShopRole.wholesaler => l10n.roleWholesaler,
        ShopRole.buyer => l10n.roleBuyer,
        ShopRole.loader => l10n.roleLoader,
        ShopRole.courier => l10n.roleCourier,
      };

  String? description(AppLocalizations l10n) => switch (this) {
        ShopRole.wholesaler => l10n.roleWholesalerDesc,
        ShopRole.buyer => l10n.roleBuyerDesc,
        _ => null,
      };

  IconData get icon => switch (this) {
        ShopRole.wholesaler => Icons.warehouse_rounded,
        ShopRole.buyer => Icons.storefront_rounded,
        ShopRole.loader => Icons.inventory_rounded,
        ShopRole.courier => Icons.local_shipping_rounded,
      };
}

/// Роли, доступные для выбора при онбординге. Грузчик и доставщик
/// добавляются позже (этап 7).
const onboardingRoles = [ShopRole.wholesaler, ShopRole.buyer];
