import 'dart:convert';
import 'dart:io';

import 'package:al_savdogar/features/catalog/domain/photo_services.dart';

/// Прозрачный PNG 1×1: настоящая картинка, которую умеет декодировать Flutter.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

/// Подменяет камеру и галерею: каждый вызов создаёт новые файлы в [directory].
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker(this.directory);

  final Directory directory;
  int _counter = 0;
  bool cancel = false;
  int cameraCalls = 0;
  int galleryCalls = 0;
  int? lastGalleryLimit;

  String _make() {
    final file = File('${directory.path}/picked_${_counter++}.jpg')..writeAsBytesSync(_png);
    return file.path;
  }

  @override
  Future<String?> takePhoto() async {
    cameraCalls++;
    return cancel ? null : _make();
  }

  @override
  Future<List<String>> pickFromGallery({required int limit}) async {
    galleryCalls++;
    lastGalleryLimit = limit;
    if (cancel) return const [];
    return [for (var i = 0; i < limit.clamp(0, 3); i++) _make()];
  }
}
