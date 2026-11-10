import '../../../core/domain/product_unit.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/money.dart';
import '../../../core/database/app_database.dart';
import '../domain/product_pricing.dart';

String unitLabel(AppLocalizations l10n, ProductUnit unit) => switch (unit) {
      ProductUnit.piece => l10n.unitPiece,
      ProductUnit.kg => l10n.unitKg,
      ProductUnit.liter => l10n.unitLiter,
      ProductUnit.meter => l10n.unitMeter,
    };

String packLabel(AppLocalizations l10n, PackKind kind) => switch (kind) {
      PackKind.box => l10n.packBox,
      PackKind.sack => l10n.packSack,
      PackKind.block => l10n.packBlock,
      PackKind.crate => l10n.packCrate,
      PackKind.pack => l10n.packPack,
    };

/// «12 000 сум / шт»
String unitPriceText(AppLocalizations l10n, Product p) =>
    '${formatAmount(p.unitPrice)} ${l10n.currencySum} / ${unitLabel(l10n, p.unit)}';

/// «Коробка · 24 шт · 250 000 сум»; пусто, если упаковки нет.
String? packLineText(AppLocalizations l10n, Product p) {
  if (!hasPack(p)) return null;
  return '${packLabel(l10n, p.packKind!)} · ${p.packSize} ${unitLabel(l10n, p.unit)} · '
      '${formatAmount(p.packPrice!)} ${l10n.currencySum}';
}
