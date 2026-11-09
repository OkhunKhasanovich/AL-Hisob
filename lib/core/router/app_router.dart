import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/catalog/catalog_page.dart';
import '../../features/debts/debts_page.dart';
import '../../features/more/more_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/orders/orders_page.dart';
import '../../features/shell/home_shell.dart';
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
