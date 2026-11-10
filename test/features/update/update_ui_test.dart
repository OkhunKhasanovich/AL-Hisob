import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/app.dart';
import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/domain/shop_role.dart';
import 'package:al_savdogar/core/settings/settings_providers.dart';
import 'package:al_savdogar/core/settings/settings_repository.dart';
import 'package:al_savdogar/features/profile/shop_profile_repository.dart';
import 'package:al_savdogar/features/update/data/update_checker.dart';
import 'package:al_savdogar/features/update/data/update_downloader.dart';
import 'package:al_savdogar/features/update/domain/apk_installer.dart';
import 'package:al_savdogar/features/update/presentation/update_controller.dart';

import '../../helpers/fake_apk_installer.dart';
import 'update_info_test.dart' show release, asset;

void main() {
  late AppDatabase db;
  late Directory dir;
  late FakeApkInstaller installer;
  late Uint8List apk;
  late Map<String, Object?>? latest;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('upd_ui');
    installer = FakeApkInstaller();
    apk = Uint8List.fromList(List.generate(2000, (i) => i % 200));
    latest = release(
      tag: 'build-9',
      name: 'Al-Savdogar 0.2.0 (9)',
      body: 'feat: catalog',
      assets: [
        asset('al-savdogar-arm64-v8a.apk', size: apk.length, digest: 'sha256:${sha256.convert(apk)}'),
      ],
    );
    // APK уже «скачан»: сети в тесте нет, загрузчик возьмёт файл из кэша.
    await File('${dir.path}/al-savdogar-9.apk').writeAsBytes(apk);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
    await db.close();
  });

  Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> openApp(WidgetTester tester, {int build = 5}) async {
    await tester.runAsync(() => ShopProfileRepository(db)
        .create(name: 'Shop', roles: {ShopRole.wholesaler}));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider
            .overrideWithValue(const AppSettingsSnapshot(locale: Locale('ru'))),
        currentBuildProvider.overrideWithValue(build),
        apkInstallerProvider.overrideWithValue(installer),
        updateCheckerProvider.overrideWithValue(UpdateChecker(
          currentBuild: build,
          abis: installer.supportedAbis,
          fetch: (_) async {
            final l = latest;
            if (l == null) throw UpdateCheckException('network');
            return l;
          },
        )),
        updateDownloaderProvider.overrideWithValue(
          () async => UpdateDownloader(directory: dir),
        ),
      ],
      child: const AlSavdogarApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
  }

  /// Плитка обновления — в самом низу длинного экрана «Ещё».
  Future<void> scrollToTile(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Обновление приложения'), 200,
        scrollable: find.byType(Scrollable).last, maxScrolls: 30);
    await tester.pump();
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> tap(WidgetTester tester, String text, {bool async = false}) async {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).last, maxScrolls: 30);
    }
    await tester.ensureVisible(finder.first);
    await tester.pump();
    if (async) {
      await tester.runAsync(() async {
        await tester.tap(finder.first);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
    } else {
      await tester.tap(finder.first);
    }
    await settle(tester);
  }

  testWidgets('при запуске предлагает обновление; «Скачать» качает в фоне, потом предлагает установить',
      (tester) async {
    await openApp(tester);

    expect(find.text('Доступно обновление'), findsOneWidget);
    expect(find.text('Версия 0.2.0 (сборка 9) готова к установке.'), findsOneWidget);
    expect(find.text('feat: catalog'), findsOneWidget);
    expect(find.textContaining('Загрузка пойдёт в фоне'), findsOneWidget);

    await tap(tester, 'Скачать', async: true);

    // Скачано, но не установлено: приложение предлагает установить.
    expect(installer.installed, isEmpty, reason: 'без согласия пользователя не ставим');
    expect(find.text('Обновление загружено'), findsOneWidget);
    await tap(tester, 'Установить', async: true);

    expect(installer.installed, hasLength(1));
    expect(installer.installed.single, endsWith('al-savdogar-9.apk'));
    expect(find.text('Обновление загружено'), findsNothing, reason: 'диалог закрылся');

    await closeApp(tester);
  });

  testWidgets('«Позже» после загрузки: файл остаётся, установить можно из «Ещё»', (tester) async {
    await openApp(tester);
    await tap(tester, 'Скачать', async: true);
    expect(find.text('Обновление загружено'), findsOneWidget);

    await tap(tester, 'Позже');
    expect(find.text('Обновление загружено'), findsNothing);
    expect(installer.installed, isEmpty);

    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    await scrollToTile(tester);
    expect(find.text('Установить'), findsOneWidget, reason: 'в плитке — готово к установке');

    await tap(tester, 'Обновление приложения');
    expect(find.text('Обновление загружено'), findsOneWidget);
    // «Установить» есть и в плитке за диалогом, и в самом диалоге — нажимаем кнопку диалога.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Установить'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await settle(tester);
    expect(installer.installed, hasLength(1));

    await closeApp(tester);
  });

  testWidgets('«Позже» закрывает диалог и ничего не запоминает', (tester) async {
    await openApp(tester);
    await tap(tester, 'Позже');

    expect(find.text('Доступно обновление'), findsNothing);
    final skipped = await tester.runAsync(() => SettingsRepository(db).readInt('update_skipped_build'));
    expect(skipped, isNull);
    expect(installer.installed, isEmpty);

    await closeApp(tester);
  });

  testWidgets('«Пропустить версию» запоминает номер сборки', (tester) async {
    await openApp(tester);
    await tap(tester, 'Пропустить версию', async: true);

    expect(find.text('Доступно обновление'), findsNothing);
    final skipped = await tester.runAsync(() => SettingsRepository(db).readInt('update_skipped_build'));
    expect(skipped, 9);

    await closeApp(tester);
  });

  testWidgets('нет разрешения: объясняем и открываем настройки Android', (tester) async {
    installer.status = InstallStatus.needsPermission;
    await openApp(tester);
    await tap(tester, 'Скачать', async: true);
    await tap(tester, 'Установить', async: true);

    expect(find.text('Разрешите установку обновлений'), findsOneWidget);
    await tap(tester, 'Открыть настройки', async: true);
    expect(installer.settingsOpened, 1);

    // Выдали разрешение — повторное нажатие запускает установку.
    installer.status = InstallStatus.started;
    await tap(tester, 'Установить', async: true);
    expect(installer.installed, hasLength(2));
    expect(find.text('Разрешите установку обновлений'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('актуальная версия: при запуске диалога нет', (tester) async {
    latest = release(tag: 'build-5');
    await openApp(tester);
    expect(find.text('Доступно обновление'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('плитка в «Ещё»: версия, ручная проверка, «последняя версия»', (tester) async {
    latest = release(tag: 'build-5');
    await openApp(tester);

    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    await scrollToTile(tester);
    expect(find.text('Обновление приложения'), findsOneWidget);
    expect(find.textContaining('(сборка 5)'), findsOneWidget);

    await tap(tester, 'Проверить обновления', async: true);
    expect(find.textContaining('Установлена последняя версия'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('плитка: ручная проверка находит обновление и открывает диалог', (tester) async {
    latest = release(tag: 'build-5');
    await openApp(tester);
    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    await scrollToTile(tester);

    latest = release(
      tag: 'build-9',
      name: 'Al-Savdogar 0.2.0 (9)',
      assets: [asset('al-savdogar-arm64-v8a.apk', size: apk.length, digest: 'sha256:${sha256.convert(apk)}')],
    );
    await tap(tester, 'Проверить обновления', async: true);

    expect(find.text('Доступно обновление'), findsOneWidget, reason: 'ровно один диалог');
    expect(find.text('Версия 0.2.0 (сборка 9) готова к установке.'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('плитка: ошибка сети показана понятным текстом', (tester) async {
    latest = release(tag: 'build-5');
    await openApp(tester);
    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    await scrollToTile(tester);

    latest = null;
    await tap(tester, 'Проверить обновления', async: true);

    expect(find.textContaining('Не удалось проверить обновления. Проверьте интернет.'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('сборка для разработки: обновления отключены, кнопки проверки нет', (tester) async {
    await openApp(tester, build: 0);
    expect(find.text('Доступно обновление'), findsNothing);

    await tester.tap(find.byTooltip('Ещё'));
    await settle(tester);
    await scrollToTile(tester);
    expect(find.textContaining('Сборка для разработки: обновления отключены'), findsOneWidget);
    expect(find.text('Проверить обновления'), findsNothing);

    await closeApp(tester);
  });
}
