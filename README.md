# Al-Savdogar

Мобильное приложение для оптовой торговли (B2B) с книгой должников. Рынок — Узбекистан.
Языки: O‘zbekcha (латиница), Русский, English, Qaraqalpaqsha. Сначала Android, затем iOS.

**Стек:** Flutter · Riverpod · go_router · Drift (SQLite, offline-first) · Material 3.
Бэкенд (FastAPI + PostgreSQL) появится на этапе 8.

## Структура

```
lib/
  main.dart, app.dart
  core/
    database/   Drift: схема, миксин SyncColumns (uuid, created/updated/deleted_at, sync_status)
    l10n/       ARB-файлы (arb/app_{en,ru,uz,kaa}.arb) и helper-ы локализации
    router/     go_router
    settings/   язык и тема (хранятся в БД)
    theme/      Material 3, светлая/тёмная
    widgets/    общие виджеты (shimmer и т.д.)
  features/     feature-first: splash, shell, debts, orders, catalog, more
drift_schemas/  дампы схемы БД по версиям (для тестов миграций)
```

## Локальный запуск

Нужен Flutter stable (`flutter --version`).

```bash
flutter pub get
dart run build_runner build      # генерация Drift-кода (.g.dart не коммитятся)
flutter run
```

Проверки (то же самое выполняет CI):

```bash
flutter analyze
flutter test
```

Локализация генерируется автоматически при `flutter pub get` / `flutter run`.
Новая строка: добавить ключ во **все четыре** `lib/core/l10n/arb/app_*.arb`.

### Изменение схемы БД

1. Поменять таблицы в `lib/core/database/app_database.dart`, увеличить `schemaVersion`.
2. Снять дамп новой версии и написать шаги миграции:

```bash
dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/
dart run drift_dev schema steps drift_schemas/ lib/core/database/schema_versions.dart
```

## CI/CD: GitHub → APK в Telegram

Workflow `.github/workflows/build-apk.yml` запускается на push в `main` и вручную
(Actions → Build APK → Run workflow). Он прогоняет `analyze` и `test`, собирает
подписанный release APK (`--split-per-abi`, в Telegram уходит arm64-v8a), проверяет,
что он < 50 МБ, и отправляет файл ботом. В подписи: версия, номер сборки, хэш и сообщение коммита.
Если сборка упала — в тот же чат приходит сообщение со ссылкой на run.
Все ABI-варианты также лежат в артефактах run на 14 дней.

Версия: `versionName` берётся из `pubspec.yaml` (`version: 0.1.0+1` → `0.1.0`),
`versionCode` — из `github.run_number`. Для split-APK Flutter добавляет к versionCode
смещение ABI (arm64-v8a: +2000), порядок возрастания сохраняется.

### 1. Release keystore (один раз)

```bash
keytool -genkeypair -v \
  -keystore al-savdogar-release.jks \
  -alias al-savdogar \
  -keyalg RSA -keysize 2048 -validity 10000
```

Задайте пароль и **используйте один и тот же для хранилища и ключа**. Сохраните
`.jks` и пароль в надёжном месте (менеджер паролей): потеряв ключ, вы не сможете
обновлять приложение поверх установленного. Файл в git не попадёт (`.gitignore`).

### 2. Закодировать в base64

```bash
base64 -w0 al-savdogar-release.jks > keystore.b64      # Linux
base64 -i al-savdogar-release.jks -o keystore.b64      # macOS
```

### 3. Telegram-бот

1. В Telegram откройте `@BotFather` → `/newbot` → получите токен.
2. Напишите вашему боту любое сообщение (или добавьте его в группу и напишите там).
3. Узнайте chat id:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates"
```

В ответе найдите `"chat":{"id":...}` (для групп id отрицательный).

### 4. Добавить secrets в репозиторий

Через GitHub CLI (`gh auth login` один раз):

```bash
gh secret set KEYSTORE_BASE64 < keystore.b64
gh secret set KEYSTORE_PASSWORD
gh secret set KEY_ALIAS --body "al-savdogar"
gh secret set KEY_PASSWORD
gh secret set TELEGRAM_BOT_TOKEN
gh secret set TELEGRAM_CHAT_ID
```

(`gh` без `--body` спросит значение интерактивно, оно не попадёт в историю shell.)
Либо вручную: репозиторий → Settings → Secrets and variables → Actions → New repository secret.

После этого удалите локальную копию `keystore.b64`:

```bash
shred -u keystore.b64 2>/dev/null || rm -P keystore.b64
```

### 5. Локальная release-сборка с подписью (по желанию)

Положите keystore в `android/app/release.jks` и создайте `android/key.properties`
(оба файла в `.gitignore`):

```properties
storeFile=app/release.jks
storePassword=...
keyAlias=al-savdogar
keyPassword=...
```

```bash
flutter build apk --release --split-per-abi
```

Без `key.properties` release-сборка подписывается debug-ключом (только для разработки).

## Этапы

0. Фундамент ✅ · 1. Онбординг · 2. Книга должников · 3. Умный поиск · 4. SMS ·
5. Каталог · 6. Заказы · 7. Грузчик и доставка · 8. Бэкенд · 9. Синхронизация · 10. Полировка → iOS
