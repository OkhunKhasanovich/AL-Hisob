import '../../../core/domain/order_status.dart';

/// Допустимые переходы между статусами.
const _transitions = <OrderStatus, Set<OrderStatus>>{
  OrderStatus.created: {OrderStatus.accepted, OrderStatus.rejected, OrderStatus.cancelled},
  OrderStatus.accepted: {OrderStatus.picking, OrderStatus.cancelled},
  OrderStatus.picking: {OrderStatus.ready, OrderStatus.cancelled},
  OrderStatus.ready: {OrderStatus.inTransit, OrderStatus.cancelled},
  OrderStatus.inTransit: {OrderStatus.delivered, OrderStatus.cancelled},
  OrderStatus.delivered: {OrderStatus.closed},
  OrderStatus.closed: {},
  OrderStatus.rejected: {},
  OrderStatus.cancelled: {},
};

/// Статусы, в которые можно перейти из [from].
Set<OrderStatus> nextStatuses(OrderStatus from) => _transitions[from] ?? const {};

bool canTransition(OrderStatus from, OrderStatus to) => nextStatuses(from).contains(to);

/// Заказ завершён и больше не меняется.
bool isFinalStatus(OrderStatus s) => nextStatuses(s).isEmpty;

/// Состав заказа можно менять, пока склад его не начал собирать.
bool canEditItems(OrderStatus s) => s == OrderStatus.created || s == OrderStatus.accepted;

/// Основной путь заказа — по нему строится шкала статусов в карточке.
const orderHappyPath = [
  OrderStatus.created,
  OrderStatus.accepted,
  OrderStatus.picking,
  OrderStatus.ready,
  OrderStatus.inTransit,
  OrderStatus.delivered,
  OrderStatus.closed,
];

/// Группы для фильтров списка заказов.
enum OrderGroup { all, fresh, inProgress, delivered, closed, cancelled }

bool inGroup(OrderStatus s, OrderGroup g) => switch (g) {
      OrderGroup.all => true,
      OrderGroup.fresh => s == OrderStatus.created,
      OrderGroup.inProgress => s == OrderStatus.accepted ||
          s == OrderStatus.picking ||
          s == OrderStatus.ready ||
          s == OrderStatus.inTransit,
      OrderGroup.delivered => s == OrderStatus.delivered,
      OrderGroup.closed => s == OrderStatus.closed,
      OrderGroup.cancelled => s == OrderStatus.rejected || s == OrderStatus.cancelled,
    };
