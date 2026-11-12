import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:al_hisob/app.dart';
import 'package:al_hisob/core/database/app_database.dart';
import 'package:al_hisob/core/domain/debt_kind.dart';
import 'package:al_hisob/core/domain/shop_role.dart';
import 'package:al_hisob/core/settings/settings_providers.dart';
import 'package:al_hisob/core/settings/settings_repository.dart';
import 'package:al_hisob/features/debts/data/debtors_repository.dart';
import 'package:al_hisob/features/profile/shop_profile_repository.dart';
import 'package:al_hisob/features/sms/data/sms_providers.dart';
import 'package:al_hisob/features/sms/data/sms_templates_repository.dart';
import 'package:al_hisob/features/sms/domain/sms_sender.dart';

import '../../helpers/fake_sms_sender.dart';

void main() {
  late AppDatabase db;
  late FakeSmsSender sender;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sender = FakeSmsSender();
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<String> addDebtor(
    WidgetTester tester,
    String name, {
    List<String> phones = const [],
    int debt = 0,
    int daysAgo = 0,
  }) async {
    final id = await tester.runAsync(() async {
      final repo = DebtorsRepository(db);
      final id = await repo.createDebtor(DebtorInput(name: name, phones: phones));
      if (debt > 0) {
        await repo.addTransaction(
          debtorId: id,
          kind: DebtKind.debt,
          amount: debt,
          occurredAt: DateTime.now().subtract(Duration(days: daysAgo)),
        );
      }
      return id;
    });
    return id!;
  }

  Future<void> openApp(WidgetTester tester, {Locale locale = const Locale('ru')}) async {
    await tester.runAsync(() => ShopProfileRepository(db)
        .create(name: 'Baraka Trade', roles: {ShopRole.wholesaler}));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        smsSenderProvider.overrideWithValue(sender),
        initialSettingsProvider.overrideWithValue(AppSettingsSnapshot(locale: locale)),
      ],
      child: const AlHisobApp(),
    ));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text, {bool async = false}) async {
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
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
    } else {
      await tester.tap(finder.first);
    }
    await settle(tester);
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('одиночная отправка: предпросмотр, отправка, запись в журнале', (tester) async {
    await addDebtor(tester, 'Alisher', phones: ['90 123 45 67'], debt: 1500000);
    await openApp(tester);

    await tapText(tester, 'Alisher');
    await tapText(tester, 'SMS-напоминание');

    // Шторка: язык по умолчанию — русский (язык приложения), в тексте — данные.
    expect(find.textContaining('Здравствуйте, Alisher!'), findsOneWidget);
    expect(find.textContaining('1 500 000 сум'), findsWidgets);
    expect(find.textContaining('Baraka Trade'), findsOneWidget);

    // Переключаем язык сообщения на узбекский — текст меняется.
    await tapText(tester, 'O‘zbekcha');
    expect(find.textContaining('Assalomu alaykum, Alisher!'), findsOneWidget);
    expect(find.textContaining("1 500 000 so'm"), findsOneWidget);

    await tapText(tester, 'Отправить SMS', async: true);

    expect(sender.sent, hasLength(1));
    final sms = sender.sent.single;
    expect(sms.phone, '+998901234567');
    expect(sms.body, startsWith('Assalomu alaykum, Alisher!'));
    expect(sms.body, isNot(contains('{')));
    expect(find.text('SMS отправлено'), findsOneWidget);

    // В карточке появилась запись истории.
    await settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('История SMS'), findsOneWidget);
    expect(find.text('Отправлено'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('ошибка отправки показана пользователю и записана в журнал', (tester) async {
    sender.nextResult = const SmsSendResult.failed('no_service');
    await addDebtor(tester, 'Bobur', phones: ['93 555 11 22'], debt: 100000);
    await openApp(tester);

    await tapText(tester, 'Bobur');
    await tapText(tester, 'SMS-напоминание');
    await tapText(tester, 'Отправить SMS', async: true);

    expect(find.text('SMS не отправлено: нет сети'), findsOneWidget);
    expect(find.text('Отправить SMS'), findsOneWidget, reason: 'шторка осталась открытой');

    final logs = await tester.runAsync(() => db.select(db.smsLogs).get());
    expect(logs!.single.error, 'no_service');

    await closeApp(tester);
  });

  testWidgets('нет разрешения: запрос, отказ — SMS не уходит', (tester) async {
    sender
      ..canSend = false
      ..grantOnRequest = false;
    await addDebtor(tester, 'Davron', phones: ['90 111 22 33'], debt: 5000);
    await openApp(tester);

    await tapText(tester, 'Davron');
    await tapText(tester, 'SMS-напоминание');
    await tapText(tester, 'Отправить SMS', async: true);

    expect(find.text('Разрешите отправку SMS'), findsOneWidget);
    await tapText(tester, 'Продолжить', async: true);

    expect(sender.requestCount, 1);
    expect(sender.sent, isEmpty);

    await closeApp(tester);
  });

  testWidgets('разрешение заблокировано навсегда: предлагаем открыть настройки', (tester) async {
    sender
      ..canSend = false
      ..grantOnRequest = false
      ..blockedForever = true;
    await addDebtor(tester, 'Eldor', phones: ['90 111 22 33'], debt: 5000);
    await openApp(tester);

    await tapText(tester, 'Eldor');
    await tapText(tester, 'SMS-напоминание');
    await tapText(tester, 'Отправить SMS', async: true);
    await tapText(tester, 'Продолжить', async: true);

    expect(find.textContaining('Доступ к SMS запрещён'), findsOneWidget);
    await tapText(tester, 'Открыть настройки', async: true);
    expect(sender.settingsOpened, 1);
    expect(sender.sent, isEmpty);

    await closeApp(tester);
  });

  testWidgets('после выдачи разрешения SMS уходит', (tester) async {
    sender
      ..canSend = false
      ..grantOnRequest = true;
    await addDebtor(tester, 'Farrux', phones: ['90 111 22 33'], debt: 5000);
    await openApp(tester);

    await tapText(tester, 'Farrux');
    await tapText(tester, 'SMS-напоминание');
    await tapText(tester, 'Отправить SMS', async: true);
    await tapText(tester, 'Продолжить', async: true);

    expect(sender.sent, hasLength(1));

    await closeApp(tester);
  });

  testWidgets('две SIM: выбор SIM передаётся отправителю', (tester) async {
    sender.sims = const [
      SimInfo(subscriptionId: 11, slot: 0, name: 'Beeline', carrier: 'Beeline', isDefaultForSms: true),
      SimInfo(subscriptionId: 12, slot: 1, name: 'Ucell', carrier: 'Ucell', isDefaultForSms: false),
    ];
    await addDebtor(tester, 'Gulnora', phones: ['90 111 22 33'], debt: 5000);
    await openApp(tester);

    await tapText(tester, 'Gulnora');
    await tapText(tester, 'SMS-напоминание');
    await tapText(tester, 'SIM 2 · Ucell');
    await tapText(tester, 'Отправить SMS', async: true);

    expect(sender.sent.single.sim, 12);

    await closeApp(tester);
  });

  testWidgets('SIM по умолчанию для SMS подставляется сама', (tester) async {
    sender.sims = const [
      SimInfo(subscriptionId: 11, slot: 0, name: 'Beeline', carrier: 'Beeline', isDefaultForSms: false),
      SimInfo(subscriptionId: 12, slot: 1, name: 'Ucell', carrier: 'Ucell', isDefaultForSms: true),
    ];
    await addDebtor(tester, 'Hasan', phones: ['90 111 22 33'], debt: 5000);
    await openApp(tester);

    await tapText(tester, 'Hasan');
    await tapText(tester, 'SMS-напоминание');
    await tapText(tester, 'Отправить SMS', async: true);

    expect(sender.sent.single.sim, 12);

    await closeApp(tester);
  });

  testWidgets('у должника нет телефона — понятное сообщение', (tester) async {
    await addDebtor(tester, 'Ilhom', debt: 5000);
    await openApp(tester);

    await tapText(tester, 'Ilhom');
    await tapText(tester, 'SMS-напоминание');

    expect(find.text('У должника нет телефона'), findsOneWidget);
    expect(sender.sent, isEmpty);

    await closeApp(tester);
  });

  testWidgets('несколько телефонов: выбираем нужный', (tester) async {
    await addDebtor(tester, 'Jasur', phones: ['90 111 22 33', '93 444 55 66'], debt: 5000);
    await openApp(tester);

    await tapText(tester, 'Jasur');
    await tapText(tester, 'SMS-напоминание');
    await tester.tap(find.widgetWithText(ChoiceChip, '+998 93 444 55 66'));
    await settle(tester);
    await tapText(tester, 'Отправить SMS', async: true);

    expect(sender.sent.single.phone, '+998934445566');

    await closeApp(tester);
  });

  testWidgets('системное окно SMS (не silent): кнопка «Открыть окно SMS»', (tester) async {
    sender = FakeSmsSender(silent: false);
    await addDebtor(tester, 'Komil', phones: ['90 111 22 33'], debt: 5000);
    await openApp(tester);

    await tapText(tester, 'Komil');
    await tapText(tester, 'SMS-напоминание');

    expect(find.text('Отправить SMS'), findsNothing);
    expect(find.text('Открыть окно SMS'), findsOneWidget);

    await closeApp(tester);
  });

  group('массовая рассылка', () {
    Future<void> openBulk(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Массовая рассылка'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
    }

    testWidgets('список: только с долгом и телефоном, просроченные выбраны заранее', (tester) async {
      await addDebtor(tester, 'Overdue Ali', phones: ['90 111 22 33'], debt: 700000, daysAgo: 45);
      await addDebtor(tester, 'Fresh Vali', phones: ['93 222 33 44'], debt: 300000, daysAgo: 2);
      await addDebtor(tester, 'No Phone', debt: 900000, daysAgo: 60);
      await addDebtor(tester, 'No Debt', phones: ['94 333 44 55']);
      await openApp(tester);
      await openBulk(tester);

      expect(find.text('Overdue Ali'), findsOneWidget);
      expect(find.text('Fresh Vali'), findsOneWidget);
      expect(find.text('No Phone'), findsNothing);
      expect(find.text('No Debt'), findsNothing);
      expect(find.text('Отправить 1 SMS'), findsOneWidget, reason: 'выбран только просроченный');

      await tapText(tester, 'Все');
      expect(find.text('Отправить 2 SMS'), findsOneWidget);
      await tapText(tester, 'Никто');
      final button = tester.widget<FilledButton>(find.ancestor(
          of: find.textContaining('Отправить 0 SMS'), matching: find.byType(FilledButton)));
      expect(button.onPressed, isNull);

      await closeApp(tester);
    });

    testWidgets('рассылка отправляет выбранным по очереди и пишет журнал', (tester) async {
      final a = await addDebtor(tester, 'Ali', phones: ['90 111 22 33'], debt: 700000, daysAgo: 45);
      final b = await addDebtor(tester, 'Vali', phones: ['93 222 33 44'], debt: 300000, daysAgo: 2);
      await openApp(tester);
      await openBulk(tester);

      await tapText(tester, 'Все');
      await tester.runAsync(() => ProviderScope.containerOf(
              tester.element(find.byType(AlHisobApp)))
          .read(smsPauseSecondsProvider.notifier)
          .set(1));
      await tapText(tester, 'Отправить 2 SMS');

      expect(find.text('Отправить 2 SMS?'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Отправить SMS'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      // первая отправка, пауза 1 с, вторая
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        await tester.pump(const Duration(milliseconds: 400));
      }

      expect(find.text('Рассылка завершена'), findsOneWidget);
      expect(sender.sent.map((s) => s.phone), ['+998901112233', '+998932223344'],
          reason: 'по убыванию долга');
      expect(find.text('Отправлено: 2'), findsOneWidget);

      final logs = await tester.runAsync(() => db.select(db.smsLogs).get());
      expect(logs!.map((l) => l.debtorId).toSet(), {a, b});

      await closeApp(tester);
    });

    testWidgets('нажатие «Остановить» прекращает рассылку', (tester) async {
      await addDebtor(tester, 'Ali', phones: ['90 111 22 33'], debt: 700000, daysAgo: 45);
      await addDebtor(tester, 'Vali', phones: ['93 222 33 44'], debt: 300000, daysAgo: 45);
      await addDebtor(tester, 'Sami', phones: ['94 333 44 55'], debt: 100000, daysAgo: 45);
      await openApp(tester);
      await openBulk(tester);

      await tester.runAsync(() => ProviderScope.containerOf(
              tester.element(find.byType(AlHisobApp)))
          .read(smsPauseSecondsProvider.notifier)
          .set(30));
      await tapText(tester, 'Отправить 3 SMS');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Отправить SMS'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(sender.sent, hasLength(1), reason: 'после первого — пауза 30 с');

      await tester.runAsync(() async {
        await tester.tap(find.text('Остановить'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Остановлено'), findsOneWidget);
      expect(sender.sent, hasLength(1));

      await closeApp(tester);
    });

    testWidgets('на устройстве без прямой отправки массовая рассылка недоступна', (tester) async {
      sender = FakeSmsSender(silent: false);
      await addDebtor(tester, 'Ali', phones: ['90 111 22 33'], debt: 700000);
      await openApp(tester);
      await openBulk(tester);

      expect(find.textContaining('Массовая рассылка требует прямой отправки'), findsOneWidget);

      await closeApp(tester);
    });
  });

  testWidgets('шаблоны: правка сохраняется и используется при отправке; сброс возвращает', (tester) async {
    await addDebtor(tester, 'Lola', phones: ['90 111 22 33'], debt: 250000);
    await openApp(tester);

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump(const Duration(milliseconds: 500));
    await tapText(tester, 'Шаблоны SMS');
    await tapText(tester, 'Русский');

    await tester.enterText(find.byType(TextField).last, 'Долг {сумма} для {имя}');
    await tester.pump();
    expect(find.textContaining('Долг 250 000'), findsNothing, reason: 'в предпросмотре пример суммы');
    expect(find.textContaining('Долг 1 500 000 сум для Alisher'), findsOneWidget);
    await tapText(tester, 'Сохранить', async: true);

    final stored = await tester.runAsync(() => SmsTemplatesRepository(db).bodyFor('ru'));
    expect(stored, 'Долг {сумма} для {имя}');
    expect(find.text('Изменён'), findsOneWidget);

    // Сброс.
    await tapText(tester, 'Русский');
    await tapText(tester, 'Вернуть по умолчанию', async: true);
    final reset = await tester.runAsync(() => SmsTemplatesRepository(db).isCustomized('ru'));
    expect(reset, isFalse);
    expect(find.text('Изменён'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('шаблон: неизвестная переменная подсвечивается, пустой не сохраняется', (tester) async {
    await openApp(tester);
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pump(const Duration(milliseconds: 500));
    await tapText(tester, 'Шаблоны SMS');
    await tapText(tester, 'English');

    await tester.enterText(find.byType(TextField).last, 'Hi {nmae}');
    await tester.pump();
    expect(find.textContaining('Неизвестные переменные: {nmae}'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '  ');
    await tester.pump();
    expect(find.text('Шаблон не может быть пустым'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'));
    expect(save.onPressed, isNull);

    await closeApp(tester);
  });
}
