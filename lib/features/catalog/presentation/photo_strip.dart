import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../data/products_repository.dart';
import 'product_image.dart';

/// Лента фото товара в форме: обложка первой, меню «обложкой/убрать», кнопка добавления.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.fileNames,
    required this.onAddCamera,
    required this.onAddGallery,
    required this.onMakeCover,
    required this.onRemove,
  });

  final List<String> fileNames;
  final VoidCallback onAddCamera;
  final VoidCallback onAddGallery;
  final ValueChanged<int> onMakeCover;
  final ValueChanged<int> onRemove;

  static const _size = 96.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final canAdd = fileNames.length < maxProductPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.photosLabel(fileNames.length, maxProductPhotos), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: _size,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < fileNames.length; i++)
                Padding(
                  key: ValueKey(fileNames[i]),
                  padding: const EdgeInsets.only(right: 8),
                  child: _Thumb(
                    fileName: fileNames[i],
                    isCover: i == 0,
                    onMakeCover: () => onMakeCover(i),
                    onRemove: () => onRemove(i),
                  ),
                ),
              if (canAdd) ...[
                _AddTile(icon: Icons.photo_camera_rounded, label: l10n.addPhotoCamera, onTap: onAddCamera),
                const SizedBox(width: 8),
                _AddTile(icon: Icons.photo_library_rounded, label: l10n.addPhotoGallery, onTap: onAddGallery),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.fileName,
    required this.isCover,
    required this.onMakeCover,
    required this.onRemove,
  });

  final String fileName;
  final bool isCover;
  final VoidCallback onMakeCover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: PhotoStrip._size,
      height: PhotoStrip._size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProductImage(fileName: fileName, cacheWidth: 300),
            if (isCover)
              Positioned(
                left: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      l10n.photoCover,
                      style: TextStyle(color: scheme.onPrimary, fontSize: 11),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: PopupMenuButton<String>(
                tooltip: '',
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black38, minimumSize: const Size(32, 32)),
                onSelected: (v) => v == 'cover' ? onMakeCover() : onRemove(),
                itemBuilder: (_) => [
                  if (!isCover) PopupMenuItem(value: 'cover', child: Text(l10n.photoMakeCover)),
                  PopupMenuItem(value: 'remove', child: Text(l10n.photoRemove)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: PhotoStrip._size,
      height: PhotoStrip._size,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(height: 4),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
