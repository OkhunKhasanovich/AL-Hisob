import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/phone.dart';
import '../domain/debt_summary.dart';
import '../domain/debtor_note.dart';
import 'balance_style.dart';
import 'debtor_avatar.dart';

/// «3 дн. назад», «Сегодня», «Вчера».
String lastOperationText(AppLocalizations l10n, int days) => switch (days) {
      0 => l10n.debtToday,
      1 => l10n.debtYesterday,
      _ => l10n.debtDaysAgo(days),
    };

/// Карточка должника в списке — только главное, в три строки: имя и долг; заметка (если есть);
/// телефон и давность последней операции. Число операций и доля оплаты — в карточке должника.
class DebtorTile extends StatelessWidget {
  const DebtorTile({
    super.key,
    required this.summary,
    required this.now,
    required this.overdue,
    this.matchedPhone,
  });

  final DebtorSummary summary;
  final DateTime now;
  final bool overdue;

  /// Телефон, по которому нашли должника (в режиме поиска).
  final String? matchedPhone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = summary.debtor;

    final days = daysSince(summary.lastOperationAt, now);
    final phone = matchedPhone ?? (summary.phones.isEmpty ? null : summary.phones.first);
    final extraPhones = matchedPhone == null && summary.phones.length > 1 ? summary.phones.length - 1 : 0;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final note = debtorNote(d);

    // Справа внизу — давность последней операции; у просроченных вместо неё значок с числом дней.
    Widget? trailing;
    if (days != null) {
      trailing = overdue
          ? _OverdueBadge(days: days)
          : _Info(icon: Icons.schedule_rounded, text: lastOperationText(l10n, days));
    }

    final contact = phone != null
        ? Row(
            children: [
              Icon(
                Icons.phone_rounded,
                size: 13,
                color: matchedPhone != null ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  extraPhones > 0 ? '${formatPhone(phone)}  +$extraPhones' : formatPhone(phone),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: matchedPhone != null
                      ? muted?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)
                      : muted,
                ),
              ),
            ],
          )
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.debtorDetails(d.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DebtorAvatar(id: d.id, name: d.name, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Имя и сумма долга.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          balanceText(l10n, summary.balance),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: balanceColor(scheme, summary.balance),
                          ),
                        ),
                      ],
                    ),
                    // Заметка — прямо под именем (до двух строк).
                    if (note != null)
                      Padding(
                        key: const ValueKey('debtor-note'),
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    // Телефон слева, давность справа — одной строкой.
                    if (contact != null || trailing != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Expanded(child: contact ?? const SizedBox.shrink()),
                            if (trailing != null) ...[const SizedBox(width: 8), trailing],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Просрочка: значок и число дней, без текста. Полная фраза («Просрочен · 45 дн.») — для дикторов.
class _OverdueBadge extends StatelessWidget {
  const _OverdueBadge({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onErrorContainer;
    return Semantics(
      label: context.l10n.debtOverdueDays(days),
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: const ValueKey('overdue-badge'),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy_rounded, size: 13, color: color),
                const SizedBox(width: 3),
                Text(
                  '$days',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
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
