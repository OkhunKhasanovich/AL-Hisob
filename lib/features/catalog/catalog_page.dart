import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/feature_placeholder.dart';

class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) => FeaturePlaceholder(
        title: context.l10n.tabCatalog,
        message: context.l10n.catalogPlaceholder,
        icon: Icons.inventory_2_rounded,
      );
}
