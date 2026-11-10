import 'dart:async';

import '../../../core/domain/sms_status.dart';
import 'sms_sender.dart';

/// Одно сообщение массовой рассылки.
class BulkSmsItem {
  const BulkSmsItem({
    required this.debtorId,
    required this.debtorName,
    required this.phone,
    required this.body,
  });

  final String debtorId;
  final String debtorName;
  final String phone;
  final String body;
}

class BulkSmsProgress {
  const BulkSmsProgress({
    required this.total,
    required this.processed,
    required this.sent,
    required this.failed,
    required this.current,
    required this.finished,
    required this.cancelled,
  });

  final int total;
  final int processed;
  final int sent;
  final int failed;

  /// Кому отправляется сейчас (или кому только что отправили).
  final BulkSmsItem? current;
  final bool finished;
  final bool cancelled;

  double get fraction => total == 0 ? 1 : processed / total;
}

typedef BulkSmsSend = Future<SmsSendResult> Function(BulkSmsItem item);

/// Рассылает сообщения по очереди с паузой между ними. Паузу и остановку
/// можно прервать: [cancel] срабатывает мгновенно, не дожидаясь конца паузы.
class BulkSmsRunner {
  BulkSmsRunner({
    required this.send,
    this.pause = const Duration(seconds: 3),
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final BulkSmsSend send;
  final Duration pause;
  final Future<void> Function(Duration) _delay;
  final Completer<void> _cancel = Completer<void>();

  bool get isCancelled => _cancel.isCompleted;

  void cancel() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  /// Поток прогресса; последнее событие имеет `finished == true`.
  Stream<BulkSmsProgress> run(List<BulkSmsItem> items) async* {
    var sent = 0, failed = 0, processed = 0;

    BulkSmsProgress snapshot(BulkSmsItem? current, {bool finished = false}) => BulkSmsProgress(
          total: items.length,
          processed: processed,
          sent: sent,
          failed: failed,
          current: current,
          finished: finished,
          cancelled: isCancelled,
        );

    for (var i = 0; i < items.length; i++) {
      if (isCancelled) break;
      final item = items[i];
      yield snapshot(item);

      SmsSendResult result;
      try {
        result = await send(item);
      } catch (e) {
        result = SmsSendResult.failed('$e');
      }
      processed++;
      if (result.status == SmsStatus.failed) {
        failed++;
      } else {
        sent++;
      }
      yield snapshot(item);

      final hasNext = i < items.length - 1;
      if (hasNext && !isCancelled && pause > Duration.zero) {
        await Future.any<void>([_delay(pause), _cancel.future]);
      }
    }
    yield snapshot(null, finished: true);
  }
}
