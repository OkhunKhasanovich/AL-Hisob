/// Выбор фото у пользователя (камера или галерея). Результат — путь к
/// уже уменьшенному и сжатому файлу (во временной папке).
abstract interface class PhotoPicker {
  /// Снимок камерой; `null`, если пользователь отменил.
  Future<String?> takePhoto();

  /// До [limit] фото из галереи; пусто, если пользователь отменил.
  Future<List<String>> pickFromGallery({required int limit});
}

/// Хранилище фото товаров в папке приложения. В БД записывается только имя файла.
abstract interface class PhotoStorage {
  /// Копирует файл в хранилище и возвращает новое имя (уникальное, `.jpg`).
  Future<String> save(String sourcePath);

  /// Удаляет файл; отсутствие файла — не ошибка.
  Future<void> delete(String fileName);

  /// Полный путь к файлу по имени (файл может и не существовать).
  String pathOf(String fileName);
}
