import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/feature_placeholder.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) => FeaturePlaceholder(
        title: context.l10n.tabOrders,
        message: context.l10n.ordersPlaceholder,
        icon: Icons.local_shipping_rounded,
      );
}
