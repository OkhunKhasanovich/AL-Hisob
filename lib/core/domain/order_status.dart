/// Статус заказа.
///
/// Путь: [created] → [accepted] → [picking] → [ready] → [inTransit] →
/// [delivered] → [closed]. Заказ можно [rejected] (продавцом, пока он новый)
/// или [cancelled] (до доставки).
enum OrderStatus {
  created,
  accepted,
  picking,
  ready,
  inTransit,
  delivered,
  closed,
  rejected,
  cancelled,
}
