import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../catalog/data/catalog_providers.dart';
import '../../catalog/domain/product_pricing.dart';
import '../../catalog/presentation/product_labels.dart';
import '../../profile/shop_name.dart';
import '../data/orders_providers.dart';
import '../domain/order_models.dart';
import 'customer_picker.dart';
import 'product_picker.dart';
import 'quantity_stepper.dart';

/// Строка корзины: позиция заказа и минимальная партия из каталога.
class _Line {
  _Line(this.item, this.minQty);

  OrderItemInput item;
  final int minQty;

  bool get belowMin => item.quantity < minQty;
}

/// Новый заказ ([orderId] == null) или правка состава существующего.
class OrderEditorPage extends ConsumerStatefulWidget {
  const OrderEditorPage({super.key, this.orderId});

  final String? orderId;

  @override
  ConsumerState<OrderEditorPage> createState() => _OrderEditorPageState();
}

class _OrderEditorPageState extends ConsumerState<OrderEditorPage> {
  Future<OrderDetails?>? _loading;

  @override
  void initState() {
    super.initState();
    final id = widget.orderId;
    if (id != null) _loading = ref.read(ordersRepositoryProvider).loadOrder(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.orderId != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? l10n.orderActionEdit : l10n.newOrder)),
      body: isEdit
          ? FutureBuilder<OrderDetails?>(
              future: _loading,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final details = snapshot.data;
                if (details == null) return const SizedBox.shrink();
                return _EditorBody(orderId: widget.orderId, initial: details);
              },
            )
          : const _EditorBody(),
    );
  }
}

class _EditorBody extends ConsumerStatefulWidget {
  const _EditorBody({this.orderId, this.initial});

  final String? orderId;
  final OrderDetails? initial;

  @override
  ConsumerState<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends ConsumerState<_EditorBody> {
  late final TextEditingController _comment;
  final List<_Line> _lines = [];
  String? _customerId;
  String? _customerName;
  bool _saving = false;

  bool get _isEdit => widget.orderId != null;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _comment = TextEditingController(text: d?.order.comment ?? '');
    if (d != null) {
      _customerId = d.order.customerId;
      _customerName = d.customerName;
      _loadLines(d);
    }
  }

  /// Позиции заказа — снимок; минимальную партию берём из каталога, если товар ещё есть.
  Future<void> _loadLines(OrderDetails d) async {
    final products = ref.read(productsRepositoryProvider);
    final lines = <_Line>[];
    for (final i in d.items) {
      var minQty = 1;
      if (i.productId != null) {
        final p = await products.loadProduct(i.productId!);
        minQty = p?.product.minOrderQuantity ?? 1;
      }
      lines.add(_Line(
        OrderItemInput(
          productId: i.productId,
          name: i.name,
          unit: i.unit,
          quantity: i.quantity,
          unitPrice: i.unitPrice,
          packSize: i.packSize,
          packPrice: i.packPrice,
        ),
        minQty,
      ));
    }
    if (mounted) setState(() => _lines.addAll(lines));
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  int get _total => orderSum(_lines.map((l) => l.item));

  bool get _canSubmit =>
      !_saving &&
      _customerId != null &&
      _lines.isNotEmpty &&
      _lines.every((l) => !l.belowMin);

  Future<void> _pickCustomer() async {
    final picked = await showCustomerPicker(context);
    if (picked != null) {
      setState(() {
        _customerId = picked.id;
        _customerName = picked.name;
      });
    }
  }

  Future<void> _addProducts() async {
    final added = {for (final l in _lines) if (l.item.productId != null) l.item.productId!};
    final picked = await showProductPicker(context, alreadyAdded: added);
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final s in picked) {
        final p = s.product;
        _lines.add(_Line(OrderItemInput.fromProduct(p, p.minOrderQuantity), p.minOrderQuantity));
      }
    });
  }

  void _setQuantity(int index, int quantity) =>
      setState(() => _lines[index].item = _lines[index].item.withQuantity(quantity));

  Future<void> _submit() async {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final repo = ref.read(ordersRepositoryProvider);
    final actor = readShopName(ref, context);
    final items = [for (final l in _lines) l.item];
    try {
      final id = widget.orderId;
      if (id == null) {
        final newId = await repo.createOrder(
          customerId: _customerId!,
          items: items,
          actorName: actor,
          comment: _comment.text,
        );
        if (mounted) context.pushReplacement(Routes.orderDetails(newId));
      } else {
        await repo.updateItems(id, items, actorName: actor, comment: _comment.text);
        if (mounted) context.pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.saveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    watchShopName(ref, context); // подписка на профиль: имя автора в истории

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                  title: Text(_customerName ?? l10n.orderChooseCustomer),
                  subtitle: Text(l10n.orderCustomerLabel),
                  trailing: _isEdit ? null : const Icon(Icons.chevron_right_rounded),
                  onTap: _isEdit ? null : _pickCustomer,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text(l10n.orderItemsTitle, style: theme.textTheme.titleMedium)),
                  TextButton.icon(
                    onPressed: _addProducts,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.addProduct),
                  ),
                ],
              ),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    l10n.orderNoItems,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else
                for (var i = 0; i < _lines.length; i++)
                  _LineCard(
                    key: ObjectKey(_lines[i]),
                    line: _lines[i],
                    onQuantity: (q) => _setQuantity(i, q),
                    onRemove: () => setState(() => _lines.removeAt(i)),
                  ),
              const SizedBox(height: 8),
              TextField(
                controller: _comment,
                maxLines: 2,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.commentLabel,
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(l10n.orderTotalLabel, style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      '${formatAmount(_total)} ${l10n.currencySum}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _saving
                      ? const SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(_isEdit ? l10n.saveButton : l10n.createOrderButton),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.onQuantity,
    required this.onRemove,
  });

  final _Line line;
  final ValueChanged<int> onQuantity;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final item = line.item;
    final unit = unitLabel(l10n, item.unit);
    final pack = item.packSize;
    final breakdown = packBreakdown(item.quantity, pack);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.name, style: theme.textTheme.titleSmall)),
                IconButton(
                  tooltip: l10n.deleteButton,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onRemove,
                ),
              ],
            ),
            Text(
              '${formatAmount(item.unitPrice)} ${l10n.currencySum} / $unit',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                QuantityStepper(quantity: item.quantity, onChanged: onQuantity),
                const SizedBox(width: 4),
                Text(unit),
                if (pack != null) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    label: Text('+$pack'),
                    onPressed: () => onQuantity(item.quantity + pack),
                  ),
                ],
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${formatAmount(item.lineTotal)} ${l10n.currencySum}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (pack != null && breakdown.packs > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${breakdown.packs} × $pack${breakdown.rest > 0 ? ' + ${breakdown.rest}' : ''} $unit',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (line.belowMin)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.orderMinQty(formatAmount(line.minQty), unit),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
