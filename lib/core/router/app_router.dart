import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/catalog/presentation/catalog_page.dart';
import '../../features/catalog/presentation/product_details_page.dart';
import '../../features/catalog/presentation/product_form_page.dart';
import '../../features/debts/presentation/debtor_details_page.dart';
import '../../features/debts/presentation/debtor_form_page.dart';
import '../../features/debts/presentation/debts_page.dart';
import '../../features/more/more_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/orders/orders_page.dart';
import '../../features/shell/home_shell.dart';
import '../../features/sms/presentation/bulk_sms_page.dart';
import '../../features/sms/presentation/sms_templates_page.dart';
import '../../features/splash/splash_page.dart';
import 'routes.dart';

GoRouter createRouter({String initialLocation = Routes.splash}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: Routes.splash,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const SplashPage(),
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (context, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const OnboardingPage(),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (context, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
      GoRoute(
        path: Routes.productNew,
        builder: (_, _) => const ProductFormPage(),
      ),
      GoRoute(
        path: '/products/:id',
        builder: (_, state) => ProductDetailsPage(productId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) => ProductFormPage(productId: state.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: Routes.bulkSms,
        builder: (_, _) => const BulkSmsPage(),
      ),
      GoRoute(
        path: Routes.smsTemplates,
        builder: (_, _) => const SmsTemplatesPage(),
      ),
      GoRoute(
        path: Routes.debtorNew,
        builder: (_, _) => const DebtorFormPage(),
      ),
      GoRoute(
        path: '/debtors/:id',
        builder: (_, state) => DebtorDetailsPage(debtorId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) => DebtorFormPage(debtorId: state.pathParameters['id']),
          ),
        ],
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        navigatorContainerBuilder: HomeShell.branchContainer,
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.debts, builder: (_, _) => const DebtsPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.orders, builder: (_, _) => const OrdersPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.catalog, builder: (_, _) => const CatalogPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.more, builder: (_, _) => const MorePage()),
          ]),
        ],
      ),
    ],
  );
}
