import 'package:image_picker/image_picker.dart';

import '../domain/photo_services.dart';

/// Размер, до которого уменьшаются фото товаров (по большей стороне), и качество JPEG.
/// Снимок с современной камеры (12+ МП, 4–6 МБ) превращается в ~150–300 КБ.
const productPhotoMaxSize = 1280.0;
const productPhotoQuality = 80;

/// Выбор фото через системные камеру и галерею (`image_picker`): отдельные
/// разрешения не нужны, их запрашивает системное приложение.
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: productPhotoMaxSize,
      maxHeight: productPhotoMaxSize,
      imageQuality: productPhotoQuality,
    );
    return file?.path;
  }

  @override
  Future<List<String>> pickFromGallery({required int limit}) async {
    if (limit <= 0) return const [];
    if (limit == 1) {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: productPhotoMaxSize,
        maxHeight: productPhotoMaxSize,
        imageQuality: productPhotoQuality,
      );
      return file == null ? const [] : [file.path];
    }
    final files = await _picker.pickMultiImage(
      maxWidth: productPhotoMaxSize,
      maxHeight: productPhotoMaxSize,
      imageQuality: productPhotoQuality,
      limit: limit,
    );
    return [for (final f in files.take(limit)) f.path];
  }
}
