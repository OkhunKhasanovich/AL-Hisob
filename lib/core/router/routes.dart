abstract final class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const onboardingSignIn = '/onboarding/sign-in';
  static const debts = '/debts';
  static const orders = '/orders';
  static const catalog = '/catalog';
  static const more = '/more';

  static const bulkSms = '/sms/bulk';
  static const smsTemplates = '/sms/templates';
  static const login = '/login';
  static const orderNew = '/orders/new';
  static String orderDetails(String id) => '/orders/$id';
  static String orderEdit(String id) => '/orders/$id/edit';
  static const productNew = '/products/new';
  static String productDetails(String id) => '/products/$id';
  static String productEdit(String id) => '/products/$id/edit';
  static const debtorNew = '/debtors/new';
  static String debtorDetails(String id) => '/debtors/$id';
  static String debtorEdit(String id) => '/debtors/$id/edit';
}
