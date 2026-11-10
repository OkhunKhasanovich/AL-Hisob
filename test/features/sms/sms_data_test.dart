import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_savdogar/core/database/app_database.dart';
import 'package:al_savdogar/core/database/sync_columns.dart';
import 'package:al_savdogar/core/domain/sms_status.dart';
import 'package:al_savdogar/features/debts/data/debtors_repository.dart';
import 'package:al_savdogar/features/sms/data/android_sms_sender.dart';
import 'package:al_savdogar/features/sms/data/composer_sms_sender.dart';
import 'package:al_savdogar/features/sms/data/sms_log_repository.dart';
import 'package:al_savdogar/features/sms/data/sms_service.dart';
import 'package:al_savdogar/features/sms/data/sms_templates_repository.dart';
import 'package:al_savdogar/features/sms/domain/reminder_text.dart';
import 'package:al_savdogar/features/sms/domain/sms_sender.dart';
import 'package:al_savdogar/features/sms/domain/sms_template.dart';

class FakeSender implements SmsSender {
  FakeSender([this.nextResult = const SmsSendResult.sent()]);

  SmsSendResult nextResult;
  final sent = <({String phone, String body, int? sim})>[];
  bool throwOnSend = false;

  @override
  bool get silent => true;
  @override
  bool get supportsSimSelection => true;
  @override
  Future<SmsPermissions> permissions() async => const SmsPermissions(canSend: true, canListSims: true);
  @override
  Future<SmsPermissions> requestPermissions() => permissions();
  @override
  Future<List<SimInfo>> listSims() async => const [];
  @override
  Future<void> openAppSettings() async {}

  @override
  Future<SmsSendResult> send({
    required String phone,
    required String body,
    int? subscriptionId,
  }) async {
    if (throwOnSend) throw StateError('modem exploded');
    sent.add((phone: phone, body: body, sim: subscriptionId));
    return nextResult;
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> newDebtor() =>
      DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Alisher', phones: ['901234567']));

  group('SmsLogRepository', () {
    test('запись содержит служебные поля, новые сверху', () async {
      final id = await newDebtor();
      final log = SmsLogRepository(db);
      final first = await log.add(
          debtorId: id, phone: '+998901234567', body: 'one', status: SmsStatus.sent);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await log.add(
          debtorId: id,
          phone: '+998901234567',
          body: 'two',
          status: SmsStatus.failed,
          error: 'no_service');

      expect(first.id, hasLength(36));
      expect(first.syncStatus, SyncStatus.pending);
      final rows = await log.forDebtor(id);
      expect(rows.map((r) => r.body), ['two', 'one']);
      expect(rows.first.status, SmsStatus.failed);
      expect(rows.first.error, 'no_service');
    });

    test('журнал не смешивает должников', () async {
      final a = await newDebtor();
      final b = await DebtorsRepository(db).createDebtor(const DebtorInput(name: 'Bobur'));
      final log = SmsLogRepository(db);
      await log.add(debtorId: a, phone: '+998901234567', body: 'to a', status: SmsStatus.sent);

      expect(await log.forDebtor(a), hasLength(1));
      expect(await log.forDebtor(b), isEmpty);
    });

    test('удаление должника скрывает его журнал (soft delete)', () async {
      final id = await newDebtor();
      final log = SmsLogRepository(db);
      await log.add(debtorId: id, phone: '+998901234567', body: 'x', status: SmsStatus.sent);

      await DebtorsRepository(db).deleteDebtor(id);

      expect(await log.forDebtor(id), isEmpty);
      expect(await db.select(db.smsLogs).get(), hasLength(1), reason: 'строка осталась для sync');
    });

    test('watchForDebtor сообщает о новых записях', () async {
      final id = await newDebtor();
      final log = SmsLogRepository(db);
      final events = <int>[];
      final sub = log.watchForDebtor(id).listen((l) => events.add(l.length));
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await log.add(debtorId: id, phone: '+998901234567', body: 'x', status: SmsStatus.sent);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.first, 0);
      expect(events.last, 1);
    });
  });

  group('SmsService', () {
    test('успешная отправка уходит отправителю с SIM и пишется в журнал', () async {
      final id = await newDebtor();
      final sender = FakeSender();
      final service = SmsService(sender: sender, log: SmsLogRepository(db));

      final result = await service.send(
          debtorId: id, phone: '+998901234567', body: 'Hello', subscriptionId: 7);

      expect(result.status, SmsStatus.sent);
      expect(sender.sent.single, (phone: '+998901234567', body: 'Hello', sim: 7));
      final logged = (await SmsLogRepository(db).forDebtor(id)).single;
      expect([logged.status, logged.body], [SmsStatus.sent, 'Hello']);
    });

    test('ошибка отправителя сохраняется в журнале', () async {
      final id = await newDebtor();
      final service = SmsService(
          sender: FakeSender(const SmsSendResult.failed('no_service')),
          log: SmsLogRepository(db));

      final result = await service.send(debtorId: id, phone: '+998901234567', body: 'x');

      expect(result.isFailure, isTrue);
      final logged = (await SmsLogRepository(db).forDebtor(id)).single;
      expect([logged.status, logged.error], [SmsStatus.failed, 'no_service']);
    });

    test('исключение отправителя превращается в failed и тоже логируется', () async {
      final id = await newDebtor();
      final sender = FakeSender()..throwOnSend = true;
      final service = SmsService(sender: sender, log: SmsLogRepository(db));

      final result = await service.send(debtorId: id, phone: '+998901234567', body: 'x');

      expect(result.status, SmsStatus.failed);
      expect(result.error, contains('modem exploded'));
      expect(await SmsLogRepository(db).forDebtor(id), hasLength(1));
    });

    test('окно SMS (iOS): статус composerOpened не считается ошибкой', () async {
      final id = await newDebtor();
      final service = SmsService(
          sender: FakeSender(const SmsSendResult(SmsStatus.composerOpened)),
          log: SmsLogRepository(db));

      final result = await service.send(debtorId: id, phone: '+998901234567', body: 'x');

      expect(result.isFailure, isFalse);
      expect(result.status.isOk, isTrue);
      expect((await SmsLogRepository(db).forDebtor(id)).single.status, SmsStatus.composerOpened);
    });
  });

  group('SmsTemplatesRepository', () {
    late SmsTemplatesRepository repo;
    setUp(() => repo = SmsTemplatesRepository(db));

    test('без правок — шаблоны по умолчанию для всех языков', () async {
      expect(await repo.all(), defaultSmsTemplates);
      expect(await repo.bodyFor('ru'), defaultSmsTemplates['ru']);
      expect(await repo.isCustomized('ru'), isFalse);
    });

    test('правка действует только для своего языка', () async {
      await repo.save('ru', 'Долг {сумма}, {имя}');
      expect(await repo.bodyFor('ru'), 'Долг {сумма}, {имя}');
      expect(await repo.bodyFor('uz'), defaultSmsTemplates['uz']);
      expect(await repo.isCustomized('ru'), isTrue);
    });

    test('повторное сохранение обновляет ту же запись', () async {
      await repo.save('en', 'First {name}');
      await repo.save('en', 'Second {name}');
      expect(await repo.bodyFor('en'), 'Second {name}');
      expect(await db.select(db.smsTemplates).get(), hasLength(1));
    });

    test('сброс возвращает шаблон по умолчанию (soft delete)', () async {
      await repo.save('kaa', 'Custom {ati}');
      await repo.resetToDefault('kaa');
      expect(await repo.bodyFor('kaa'), defaultSmsTemplates['kaa']);
      expect(await repo.isCustomized('kaa'), isFalse);
      expect((await db.select(db.smsTemplates).get()).single.deletedAt, isNotNull);
    });

    test('текст, равный шаблону по умолчанию, снимает правку', () async {
      await repo.save('ru', 'Custom');
      await repo.save('ru', defaultSmsTemplates['ru']!);
      expect(await repo.isCustomized('ru'), isFalse);
    });

    test('после сброса можно снова править', () async {
      await repo.save('uz', 'A {ism}');
      await repo.resetToDefault('uz');
      await repo.save('uz', 'B {ism}');
      expect(await repo.bodyFor('uz'), 'B {ism}');
    });

    test('пустой шаблон отклоняется', () {
      expect(() => repo.save('ru', '   '), throwsArgumentError);
    });
  });

  group('buildReminderText', () {
    test('подставляет данные, нормализует апострофы', () {
      final text = buildReminderText(
        template: 'Salom {ism}, {summa} to‘lang {sana} gacha. {dokon}',
        language: 'uz',
        debtorName: 'Ali',
        amount: 250000,
        shopName: 'Baraka',
        dueDate: DateTime(2026, 11, 13),
      );
      expect(text, "Salom Ali, 250 000 so'm to'lang 13.11.2026 gacha. Baraka");
    });

    test('срок оплаты по умолчанию — через 3 дня, без времени', () {
      expect(defaultDueDate(DateTime(2026, 11, 10, 17, 45)), DateTime(2026, 11, 13));
      expect(defaultDueDate(DateTime(2026, 12, 30, 9)), DateTime(2027, 1, 2));
    });
  });

  group('AndroidSmsSender: разбор ответов нативной части', () {
    test('parseSendResult', () {
      expect(parseSendResult({'status': 'sent'}).status, SmsStatus.sent);
      expect(parseSendResult({'status': 'no_permission'}).error, 'no_permission');
      final failed = parseSendResult({'status': 'failed', 'message': 'radio_off'});
      expect([failed.status, failed.error], [SmsStatus.failed, 'radio_off']);
      expect(parseSendResult({'status': 'failed'}).error, 'failed');
      expect(parseSendResult(null).isFailure, isTrue);
      expect(parseSendResult({'status': '???'}).error, 'unknown_response');
    });

    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('uz.alsavdogar.app/sms');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('send передаёт аргументы и возвращает результат', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return {'status': 'sent'};
      });

      final result = await AndroidSmsSender()
          .send(phone: '+998901234567', body: 'Hi', subscriptionId: 3);

      expect(result.status, SmsStatus.sent);
      expect(received!.method, 'sendSms');
      expect(received!.arguments, {'phone': '+998901234567', 'body': 'Hi', 'subscriptionId': 3});
    });

    test('PlatformException и отсутствие плагина не бросают исключений', () async {
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'boom', message: 'bad'));
      final r1 = await AndroidSmsSender().send(phone: '+998901234567', body: 'x');
      expect([r1.status, r1.error], [SmsStatus.failed, 'bad']);

      messenger.setMockMethodCallHandler(channel, null);
      final r2 = await AndroidSmsSender().send(phone: '+998901234567', body: 'x');
      expect(r2.isFailure, isTrue);
    });

    test('permissions и listSims разбирают ответ', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'permissions' || 'requestPermissions' =>
            {'canSend': true, 'canListSims': false, 'blockedForever': true},
          'listSims' => [
              {'subscriptionId': 12, 'slot': 1, 'name': 'Ucell', 'carrier': 'Ucell', 'isDefaultForSms': false},
              {'subscriptionId': 11, 'slot': 0, 'name': '', 'carrier': 'Beeline', 'isDefaultForSms': true},
            ],
          _ => null,
        };
      });
      final sender = AndroidSmsSender();

      final p = await sender.permissions();
      expect([p.canSend, p.canListSims, p.blockedForever], [true, false, true]);

      final sims = await sender.listSims();
      expect(sims.map((s) => s.slot), [0, 1], reason: 'по слотам');
      expect(sims.first.label, 'SIM 1 · Beeline');
      expect(sims.first.isDefaultForSms, isTrue);
      expect(sims.last.label, 'SIM 2 · Ucell');
    });

    test('без нативной части: разрешений нет, SIM пусто, исключений нет', () async {
      final sender = AndroidSmsSender();
      final p = await sender.permissions();
      expect([p.canSend, p.canListSims], [false, false]);
      expect((await sender.requestPermissions()).canSend, isFalse);
      expect(await sender.listSims(), isEmpty);
      await sender.openAppSettings();
    });
  });

  test('composerUri собирает sms: с телом', () {
    final uri = composerUri('+998901234567', 'Salom, 100 so\'m');
    expect(uri.scheme, 'sms');
    expect(uri.path, '+998901234567');
    expect(uri.queryParameters['body'], "Salom, 100 so'm");
  });
}
