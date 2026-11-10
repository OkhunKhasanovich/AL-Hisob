import 'dart:io';

import '../../../core/database/sync_columns.dart';
import '../domain/photo_services.dart';

class LocalPhotoStorage implements PhotoStorage {
  LocalPhotoStorage(this.directory);

  final Directory directory;

  @override
  Future<String> save(String sourcePath) async {
    await directory.create(recursive: true);
    final name = '${generateId()}.jpg';
    await File(sourcePath).copy('${directory.path}/$name');
    return name;
  }

  @override
  Future<void> delete(String fileName) async {
    // Имя приходит из БД, но на всякий случай не даём выйти из папки хранилища.
    if (fileName.contains('/') || fileName.contains('\\') || fileName.contains('..')) return;
    final file = File('${directory.path}/$fileName');
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // не страшно
    }
  }

  @override
  String pathOf(String fileName) => '${directory.path}/$fileName';
}
