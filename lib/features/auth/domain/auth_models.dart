/// Адрес API (`--dart-define=API_BASE_URL=https://api.example.com` в CI).
/// Пусто — сервера нет (локальные сборки): вход и предложение войти скрыты.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

bool get isServerConfigured => apiBaseUrl.isNotEmpty;

class AuthUser {
  const AuthUser({required this.id, required this.phone, this.name});

  factory AuthUser.fromJson(Map<String, Object?> json) => AuthUser(
        id: json['id']! as String,
        phone: json['phone']! as String,
        name: json['name'] as String?,
      );

  final String id;

  /// `+998901234567`
  final String phone;
  final String? name;

  Map<String, Object?> toJson() => {'id': id, 'phone': phone, 'name': name};
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
  });

  factory AuthTokens.fromJson(Map<String, Object?> json) => AuthTokens(
        accessToken: json['accessToken']! as String,
        refreshToken: json['refreshToken']! as String,
        accessExpiresAt: DateTime.fromMillisecondsSinceEpoch(json['accessExpiresAtMs']! as int),
      );

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;

  /// Access-токен скоро истечёт (или уже истёк) — пора обновить.
  bool expiresWithin(Duration margin, {DateTime? now}) =>
      !accessExpiresAt.isAfter((now ?? DateTime.now()).add(margin));

  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessExpiresAtMs': accessExpiresAt.millisecondsSinceEpoch,
      };
}

/// Вошедший пользователь и его токены.
class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  factory AuthSession.fromJson(Map<String, Object?> json) => AuthSession(
        user: AuthUser.fromJson((json['user']! as Map).cast<String, Object?>()),
        tokens: AuthTokens.fromJson((json['tokens']! as Map).cast<String, Object?>()),
      );

  final AuthUser user;
  final AuthTokens tokens;

  AuthSession withTokens(AuthTokens t) => AuthSession(user: user, tokens: t);

  Map<String, Object?> toJson() => {'user': user.toJson(), 'tokens': tokens.toJson()};
}
