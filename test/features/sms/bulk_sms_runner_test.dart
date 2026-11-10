import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/features/sms/domain/bulk_sms_runner.dart';
import 'package:al_savdogar/features/sms/domain/sms_sender.dart';

BulkSmsItem item(int i) => BulkSmsItem(
      debtorId: 'd$i',
      debtorName: 'Debtor $i',
      phone: '+99890000000$i',
      body: 'text $i',
    );

void main() {
  test('отправляет всем по порядку, пауза — между сообщениями, но не после последнего', () async {
    final order = <String>[];
    final pauses = <Duration>[];
    final runner = BulkSmsRunner(
      pause: const Duration(seconds: 3),
      send: (i) async {
        order.add(i.debtorId);
        return const SmsSendResult.sent();
      },
      delay: (d) async => pauses.add(d),
    );

    final events = await runner.run([item(1), item(2), item(3)]).toList();

    expect(order, ['d1', 'd2', 'd3']);
    expect(pauses, [const Duration(seconds: 3), const Duration(seconds: 3)]);
    final last = events.last;
    expect(last.finished, isTrue);
    expect(last.cancelled, isFalse);
    expect([last.total, last.processed, last.sent, last.failed], [3, 3, 3, 0]);
    expect(last.fraction, 1);
  });

  test('прогресс растёт по ходу рассылки и называет текущего получателя', () async {
    final runner = BulkSmsRunner(
      pause: Duration.zero,
      send: (_) async => const SmsSendResult.sent(),
    );
    final events = await runner.run([item(1), item(2)]).toList();

    final processed = events.map((e) => e.processed).toList();
    expect(processed, [0, 1, 1, 2, 2]);
    expect(events.first.current?.debtorId, 'd1');
    expect(events.last.current, isNull);
  });

  test('ошибки считаются отдельно, рассылка продолжается', () async {
    final runner = BulkSmsRunner(
      pause: Duration.zero,
      send: (i) async => i.debtorId == 'd2'
          ? const SmsSendResult.failed('no network')
          : const SmsSendResult.sent(),
    );
    final last = (await runner.run([item(1), item(2), item(3)]).toList()).last;

    expect([last.sent, last.failed, last.processed], [2, 1, 3]);
  });

  test('исключение отправителя не ломает рассылку', () async {
    final runner = BulkSmsRunner(
      pause: Duration.zero,
      send: (i) async {
        if (i.debtorId == 'd1') throw StateError('boom');
        return const SmsSendResult.sent();
      },
    );
    final last = (await runner.run([item(1), item(2)]).toList()).last;

    expect([last.sent, last.failed], [1, 1]);
  });

  test('остановка во время паузы срабатывает сразу, остальным не отправляется', () async {
    final sentTo = <String>[];
    final pauseStarted = Completer<void>();
    late BulkSmsRunner runner;
    runner = BulkSmsRunner(
      pause: const Duration(hours: 1),
      send: (i) async {
        sentTo.add(i.debtorId);
        return const SmsSendResult.sent();
      },
      // Пауза «бесконечная»: без cancel тест бы завис.
      delay: (_) {
        pauseStarted.complete();
        return Completer<void>().future;
      },
    );

    final future = runner.run([item(1), item(2), item(3)]).toList();
    await pauseStarted.future;
    runner.cancel();
    final events = await future.timeout(const Duration(seconds: 5));

    expect(sentTo, ['d1']);
    final last = events.last;
    expect(last.cancelled, isTrue);
    expect(last.finished, isTrue);
    expect([last.sent, last.processed, last.total], [1, 1, 3]);
    expect(runner.isCancelled, isTrue);
  });

  test('отмена до старта — ничего не отправляется', () async {
    var calls = 0;
    final runner = BulkSmsRunner(send: (_) async {
      calls++;
      return const SmsSendResult.sent();
    })
      ..cancel();
    final last = (await runner.run([item(1)]).toList()).last;

    expect(calls, 0);
    expect(last.cancelled, isTrue);
  });

  test('пустой список завершается сразу', () async {
    final runner = BulkSmsRunner(send: (_) async => const SmsSendResult.sent());
    final events = await runner.run(const []).toList();

    expect(events, hasLength(1));
    expect(events.single.finished, isTrue);
    expect(events.single.fraction, 1);
  });

  test('нулевая пауза — delay не вызывается', () async {
    var delays = 0;
    final runner = BulkSmsRunner(
      pause: Duration.zero,
      send: (_) async => const SmsSendResult.sent(),
      delay: (_) async => delays++,
    );
    await runner.run([item(1), item(2)]).toList();
    expect(delays, 0);
  });
}
