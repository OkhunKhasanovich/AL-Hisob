import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/update/data/update_checker.dart';

import 'update_info_test.dart' show release;

void main() {
  UpdateChecker checker({
    required int current,
    required Future<Map<String, Object?>?> Function(Uri) fetch,
    List<String> abis = const ['arm64-v8a'],
  }) =>
      UpdateChecker(
        currentBuild: current,
        abis: () async => abis,
        repository: 'owner/repo',
        fetch: fetch,
      );

  test('сборка для разработки: сеть не трогаем', () async {
    var calls = 0;
    final c = checker(current: 0, fetch: (_) async {
      calls++;
      return release();
    });
    expect(await c.check(), isNull);
    expect(calls, 0);
  });

  test('запрашивает latest нужного репозитория', () async {
    Uri? requested;
    await checker(current: 1, fetch: (uri) async {
      requested = uri;
      return release();
    }).check();
    expect(requested.toString(), 'https://api.github.com/repos/owner/repo/releases/latest');
  });

  test('есть новее — возвращает информацию', () async {
    final info = await checker(current: 5, fetch: (_) async => release(tag: 'build-12')).check();
    expect(info!.build, 12);
  });

  test('та же сборка и старее — обновления нет', () async {
    expect(await checker(current: 12, fetch: (_) async => release(tag: 'build-12')).check(), isNull);
    expect(await checker(current: 30, fetch: (_) async => release(tag: 'build-12')).check(), isNull);
  });

  test('релизов ещё нет (404) — обновления нет', () async {
    expect(await checker(current: 5, fetch: (_) async => null).check(), isNull);
  });

  test('релиз без APK под архитектуру телефона — обновления нет', () async {
    final c = checker(current: 5, abis: ['riscv64'], fetch: (_) async => release());
    expect(await c.check(), isNull);
  });

  test('ошибка сети пробрасывается', () async {
    final c = checker(current: 5, fetch: (_) async => throw UpdateCheckException('timeout'));
    expect(c.check(), throwsA(isA<UpdateCheckException>()));
  });
}
