import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../profile/profile_providers.dart';
import '../profile/shop_profile_form.dart';

class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              children: [
                FadeSlideIn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Hero(
                        tag: 'app-logo',
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(Icons.storefront_rounded, size: 40, color: scheme.onPrimary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.onboardingTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.onboardingSubtitle,
                        style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 150),
                  child: ShopProfileForm(
                    submitLabel: l10n.continueButton,
                    onSubmit: (name, role) async {
                      await ref
                          .read(shopProfileRepositoryProvider)
                          .create(name: name, roles: {role});
                      if (context.mounted) context.go(Routes.debts);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
