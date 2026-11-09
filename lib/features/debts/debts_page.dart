import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/feature_placeholder.dart';

class DebtsPage extends StatelessWidget {
  const DebtsPage({super.key});

  @override
  Widget build(BuildContext context) => FeaturePlaceholder(
        title: context.l10n.tabDebts,
        message: context.l10n.debtsPlaceholder,
        icon: Icons.menu_book_rounded,
      );
}
