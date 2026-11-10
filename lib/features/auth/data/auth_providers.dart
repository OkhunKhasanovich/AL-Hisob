import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/auth_api.dart';
import 'http_auth_api.dart';
import 'token_store.dart';

/// Переопределяются в тестах.
final authApiProvider = Provider<AuthApi>((ref) => HttpAuthApi());

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Открывает внешнее приложение/браузер (ссылку на Telegram-бота).
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Пауза между опросами сервера при входе; в тестах заменяется на мгновенную.
final loginPollDelayProvider = Provider<Future<void> Function(Duration)>(
  (ref) => Future<void>.delayed,
);
