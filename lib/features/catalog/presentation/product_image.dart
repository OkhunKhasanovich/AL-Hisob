import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog_providers.dart';

/// Фото товара из папки приложения. Без файла (или если он не читается)
/// показывает нейтральную заглушку.
class ProductImage extends ConsumerWidget {
  const ProductImage({
    super.key,
    required this.fileName,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.iconSize = 40,
  });

  final String? fileName;
  final BoxFit fit;

  /// Ширина декодирования (экономит память в списках).
  final int? cacheWidth;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.image_outlined, size: iconSize, color: scheme.onSurfaceVariant),
      ),
    );

    final dir = ref.watch(photoDirectoryProvider).value;
    if (fileName == null || dir == null) return placeholder;

    return Image.file(
      File('${dir.path}/$fileName'),
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
