abstract final class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const debts = '/debts';
  static const orders = '/orders';
  static const catalog = '/catalog';
  static const more = '/more';

  static const bulkSms = '/sms/bulk';
  static const smsTemplates = '/sms/templates';
  static const debtorNew = '/debtors/new';
  static String debtorDetails(String id) => '/debtors/$id';
  static String debtorEdit(String id) => '/debtors/$id/edit';
}
