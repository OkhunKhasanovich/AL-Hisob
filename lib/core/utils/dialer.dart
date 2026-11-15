import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Открывает набор номера с подставленным номером (без звонка: человек сам нажимает «вызов»).
/// Возвращает `false`, если на телефоне нет приложения для звонков. Переопределяется в тестах.
final phoneDialerProvider = Provider<Future<bool> Function(String phone)>(
  (ref) => (phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      return await launchUrl(uri);
    } on Exception {
      return false;
    }
  },
);
