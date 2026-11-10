import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/domain/shop_role.dart';
import '../../core/l10n/l10n.dart';
import 'profile_providers.dart';
import 'shop_profile_form.dart';
import 'shop_role_l10n.dart';

/// Карточка «Ваш бизнес» с названием, ролью и кнопкой редактирования.
class ProfileCard extends ConsumerWidget {
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(shopProfileProvider).value;
    if (profile == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = profile.roles.map((r) => r.label(l10n)).join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                profile.roles.first.icon,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.profileSectionTitle, style: theme.textTheme.labelMedium),
                  Text(
                    profile.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    roles,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.editButton,
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => _edit(context, profile),
            ),
          ],
        ),
      ),
    );
  }

  void _edit(BuildContext context, ShopProfile profile) {
    showModalBottomSheet<void>(
      // Поверх стеклянной панели вкладок, а не под ней.
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: ShopProfileForm(
              submitLabel: context.l10n.saveButton,
              initialName: profile.name,
              initialRole: profile.roles.contains(ShopRole.wholesaler)
                  ? ShopRole.wholesaler
                  : ShopRole.buyer,
              onSubmit: (name, role) async {
                await ref
                    .read(shopProfileRepositoryProvider)
                    .update(id: profile.id, name: name, roles: {role});
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
          ),
        ),
      ),
    );
  }
}
