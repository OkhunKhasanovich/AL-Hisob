import 'package:al_savdogar/features/sms/domain/sms_sender.dart';

/// Отправитель для тестов: запоминает сообщения, разрешения и SIM настраиваются.
class FakeSmsSender implements SmsSender {
  FakeSmsSender({
    this.nextResult = const SmsSendResult.sent(),
    this.canSend = true,
    this.grantOnRequest = true,
    this.blockedForever = false,
    this.sims = const [],
    this.silent = true,
  });

  SmsSendResult nextResult;
  bool canSend;
  bool grantOnRequest;
  bool blockedForever;
  List<SimInfo> sims;
  bool throwOnSend = false;

  final sent = <({String phone, String body, int? sim})>[];
  int requestCount = 0;
  int settingsOpened = 0;

  @override
  final bool silent;

  @override
  bool get supportsSimSelection => sims.isNotEmpty;

  SmsPermissions get _state => SmsPermissions(
        canSend: canSend,
        canListSims: canSend,
        blockedForever: !canSend && blockedForever,
      );

  @override
  Future<SmsPermissions> permissions() async => _state;

  @override
  Future<SmsPermissions> requestPermissions() async {
    requestCount++;
    if (grantOnRequest) canSend = true;
    return _state;
  }

  @override
  Future<List<SimInfo>> listSims() async => sims;

  @override
  Future<void> openAppSettings() async => settingsOpened++;

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
