import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/product_unit.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_input_formatter.dart';
import '../data/catalog_providers.dart';
import '../data/products_repository.dart';
import '../domain/photo_services.dart';
import '../domain/product_summary.dart';
import 'photo_strip.dart';
import 'product_labels.dart';

/// Создание ([productId] == null) и редактирование товара.
class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({super.key, this.productId});

  final String? productId;

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  Future<ProductSummary?>? _loading;

  @override
  void initState() {
    super.initState();
    final id = widget.productId;
    if (id != null) {
      _loading = ref.read(productsRepositoryProvider).loadProduct(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.productId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l10n.productEditTitle : l10n.productNewTitle),
      ),
      body: isEdit
          ? FutureBuilder<ProductSummary?>(
              future: _loading,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final summary = snapshot.data;
                if (summary == null) return const SizedBox.shrink();
                return _ProductFormBody(
                  productId: widget.productId,
                  initial: summary,
                );
              },
            )
          : const _ProductFormBody(),
    );
  }
}

class _ProductFormBody extends ConsumerStatefulWidget {
  const _ProductFormBody({this.productId, this.initial});

  final String? productId;
  final ProductSummary? initial;

  @override
  ConsumerState<_ProductFormBody> createState() => _ProductFormBodyState();
}

class _ProductFormBodyState extends ConsumerState<_ProductFormBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _unitPrice;
  late final TextEditingController _packSize;
  late final TextEditingController _packPrice;
  late final TextEditingController _minOrder;

  late ProductUnit _unit;
  late PackKind _packKind;
  late bool _soldInPacks;
  late bool _inStock;

  /// Имена файлов в порядке показа; первое — обложка.
  late List<String> _photos;

  /// Файлы, добавленные в этой сессии: если форму закроют без сохранения, удаляем с диска.
  final Set<String> _addedThisSession = {};
  bool _saved = false;
  bool _saving = false;
  PhotoStorage? _storage;

  @override
  void initState() {
    super.initState();
    final p = widget.initial?.product;
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _unitPrice = TextEditingController(
      text: p == null ? '' : formatAmount(p.unitPrice),
    );
    _packSize = TextEditingController(text: p?.packSize?.toString() ?? '');
    _packPrice = TextEditingController(
      text: p?.packPrice == null ? '' : formatAmount(p!.packPrice!),
    );
    _minOrder = TextEditingController(
      text: (p?.minOrderQuantity ?? 1).toString(),
    );
    _unit = p?.unit ?? ProductUnit.piece;
    _packKind = p?.packKind ?? PackKind.box;
    _soldInPacks = p?.packKind != null;
    _inStock = p?.inStock ?? true;
    _photos = [
      for (final ph in widget.initial?.photos ?? const []) ph.fileName,
    ];

    // Живая подсказка о цене за единицу в упаковке.
    for (final c in [_unitPrice, _packSize, _packPrice]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _category,
      _description,
      _unitPrice,
      _packSize,
      _packPrice,
      _minOrder,
    ]) {
      c.dispose();
    }
    if (!_saved) {
      final storage = _storage;
      if (storage != null) {
        for (final f in _addedThisSession) {
          storage.delete(f);
        }
      }
    }
    super.dispose();
  }

  Future<PhotoStorage> _photoStorage() async {
    final existing = _storage;
    if (existing != null) return existing;
    final created = await ref.read(photoStorageProvider.future);
    _storage = created;
    return created;
  }

  Future<void> _addPhotos(
    Future<List<String>> Function(PhotoPicker picker, int free) pick,
  ) async {
    final l10n = context.l10n;
    final free = maxProductPhotos - _photos.length;
    if (free <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.photoLimitReached(maxProductPhotos))),
        );
      return;
    }
    final storage = await _photoStorage();
    final paths = await pick(ref.read(photoPickerProvider), free);
    if (!mounted) return;
    for (final path in paths.take(free)) {
      final name = await storage.save(path);
      _addedThisSession.add(name);
      if (!mounted) return;
      setState(() => _photos = [..._photos, name]);
    }
  }

  Future<void> _removePhoto(int index) async {
    final name = _photos[index];
    setState(() => _photos = [..._photos]..removeAt(index));
    if (_addedThisSession.remove(name)) {
      await (await _photoStorage()).delete(name);
    }
  }

  void _makeCover(int index) {
    HapticFeedback.selectionClick();
    final list = [..._photos];
    list.insert(0, list.removeAt(index));
    setState(() => _photos = list);
  }

  int? _parsedUnitPrice() {
    final v = parseAmount(_unitPrice.text);
    return (v == null || v <= 0) ? null : v;
  }

  int? _parsedPackSize() {
    final v = int.tryParse(_packSize.text.trim());
    return (v == null || v < 2) ? null : v;
  }

  int? _parsedPackPrice() {
    final v = parseAmount(_packPrice.text);
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final repo = ref.read(productsRepositoryProvider);
    final input = ProductInput(
      name: _name.text,
      category: _category.text,
      description: _description.text,
      unit: _unit,
      unitPrice: _parsedUnitPrice()!,
      pack: _soldInPacks
          ? PackInput(
              kind: _packKind,
              size: _parsedPackSize()!,
              price: _parsedPackPrice()!,
            )
          : null,
      minOrderQuantity: int.parse(_minOrder.text.trim()),
      inStock: _inStock,
    );

    try {
      final id = widget.productId;
      if (id == null) {
        final newId = await repo.createProduct(input, photoFiles: _photos);
        _saved = true;
        if (mounted) context.pushReplacement(Routes.productDetails(newId));
      } else {
        await repo.updateProduct(id, input);
        final removed = await repo.replacePhotos(id, _photos);
        _saved = true;
        final storage = await _photoStorage();
        for (final f in removed) {
          await storage.delete(f);
        }
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

  InputDecoration _decoration(
    String label, {
    IconData? icon,
    String? suffix,
    String? helper,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: icon == null ? null : Icon(icon),
    suffixText: suffix,
    helperText: helper,
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final categories = ref.watch(catalogCategoriesProvider);
    final unitText = unitLabel(l10n, _unit);

    // Подсказка по упаковке: цена за единицу и скидка.
    final size = _parsedPackSize(),
        packPrice = _parsedPackPrice(),
        unitPrice = _parsedUnitPrice();
    String? packHint;
    if (_soldInPacks && size != null && packPrice != null) {
      final per =
          '${formatAmount((packPrice / size).round())} ${l10n.currencySum}';
      packHint = l10n.packPerUnitHint(per);
      if (unitPrice != null && packPrice < size * unitPrice) {
        final percent =
            ((size * unitPrice - packPrice) * 100 / (size * unitPrice)).round();
        if (percent > 0) packHint = '$packHint · ${l10n.packDiscount(percent)}';
      }
    }

    return Form(
      key: _formKey,
      // Не ListView: он убирает поля за экраном, и validate() их бы не проверял.
      child: SingleChildScrollView(
        key: const ValueKey('product-form-list'),
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhotoStrip(
              fileNames: _photos,
              onAddCamera: () => _addPhotos((picker, _) async {
                final path = await picker.takePhoto();
                return path == null ? const [] : [path];
              }),
              onAddGallery: () => _addPhotos(
                (picker, free) => picker.pickFromGallery(limit: free),
              ),
              onMakeCover: _makeCover,
              onRemove: _removePhoto,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLength: 120,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.productNameError
                  : null,
              decoration: _decoration(
                l10n.productNameLabel,
                icon: Icons.label_rounded,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _category,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLength: 60,
              decoration: _decoration(
                l10n.productCategoryLabel,
                icon: Icons.category_rounded,
              ),
            ),
            if (categories.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in categories.take(8))
                    ActionChip(
                      label: Text(c),
                      onPressed: () => setState(() => _category.text = c),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Text(l10n.productUnitLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final u in ProductUnit.values)
                  ChoiceChip(
                    label: Text(unitLabel(l10n, u)),
                    selected: _unit == u,
                    onSelected: (_) => setState(() => _unit = u),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _unitPrice,
              keyboardType: TextInputType.number,
              inputFormatters: const [AmountInputFormatter()],
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (_) =>
                  _parsedUnitPrice() == null ? l10n.productPriceError : null,
              decoration: _decoration(
                '${l10n.productUnitPriceLabel} / $unitText',
                icon: Icons.payments_rounded,
                suffix: l10n.currencySum,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.productSoldInPacks),
              value: _soldInPacks,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _soldInPacks = v);
              },
            ),
            if (_soldInPacks) ...[
              Text(l10n.packKindLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final k in PackKind.values)
                    ChoiceChip(
                      label: Text(packLabel(l10n, k)),
                      selected: _packKind == k,
                      onSelected: (_) => setState(() => _packKind = k),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _packSize,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (_) =>
                    _parsedPackSize() == null ? l10n.packSizeError : null,
                decoration: _decoration(
                  l10n.packSizeLabel,
                  icon: Icons.inventory_2_rounded,
                  suffix: unitText,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _packPrice,
                keyboardType: TextInputType.number,
                inputFormatters: const [AmountInputFormatter()],
                textInputAction: TextInputAction.next,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (_) =>
                    _parsedPackPrice() == null ? l10n.productPriceError : null,
                decoration: _decoration(
                  l10n.packPriceLabel,
                  icon: Icons.payments_outlined,
                  suffix: l10n.currencySum,
                  helper: packHint,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _minOrder,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n < 1) ? l10n.minOrderError : null;
              },
              decoration: _decoration(
                l10n.minOrderLabel,
                icon: Icons.shopping_basket_rounded,
                suffix: unitText,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.inStockLabel),
              value: _inStock,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _inStock = v);
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _description,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(
                l10n.productDescriptionLabel,
                icon: Icons.notes_rounded,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(l10n.saveButton),
            ),
          ],
        ),
      ),
    );
  }
}
