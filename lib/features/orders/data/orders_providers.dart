import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_providers.dart';
import '../domain/order_models.dart';
import '../domain/order_workflow.dart';
import 'orders_repository.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(appDatabaseProvider)),
);

/// Все заказы (новые сверху); обновляется при изменениях в БД.
final orderSummariesProvider = StreamProvider<List<OrderSummary>>(
  (ref) => ref.watch(ordersRepositoryProvider).watchSummaries(),
);

final orderDetailsProvider = StreamProvider.autoDispose.family<OrderDetails?, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).watchOrder(id),
);

class SelectedOrderGroup extends Notifier<OrderGroup> {
  @override
  OrderGroup build() => OrderGroup.all;

  void select(OrderGroup group) => state = group;
}

final selectedOrderGroupProvider =
    NotifierProvider<SelectedOrderGroup, OrderGroup>(SelectedOrderGroup.new);

/// Заказы выбранной группы; `null`, пока данные грузятся.
final visibleOrdersProvider = Provider<List<OrderSummary>?>((ref) {
  final all = ref.watch(orderSummariesProvider).value;
  if (all == null) return null;
  final group = ref.watch(selectedOrderGroupProvider);
  return [for (final o in all) if (inGroup(o.order.status, group)) o];
});
