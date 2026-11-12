import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/phone.dart';
import '../domain/debt_summary.dart';
import 'balance_style.dart';
import 'debtor_avatar.dart';

/// «3 дн. назад», «Сегодня», «Вчера».
String lastOperationText(AppLocalizations l10n, int days) => switch (days) {
      0 => l10n.debtToday,
      1 => l10n.debtYesterday,
      _ => l10n.debtDaysAgo(days),
    };

/// Карточка должника в списке: кто, сколько должен, когда была последняя операция,
/// сколько операций и какая часть выданного уже возвращена.
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.debtorDetails(d.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DebtorAvatar(id: d.id, name: d.name, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (phone != null || d.shopName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(
                                  phone != null ? Icons.phone_rounded : Icons.storefront_rounded,
                                  size: 13,
                                  color: matchedPhone != null ? scheme.primary : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                // «+998 90 123 45 67 • Магазин» в одну строку; при нехватке места
                                // сокращается название магазина, а не номер.
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        if (phone != null)
                                          TextSpan(
                                            text: extraPhones > 0
                                                ? '${formatPhone(phone)}  +$extraPhones'
                                                : formatPhone(phone),
                                            style: matchedPhone != null
                                                ? TextStyle(
                                                    color: scheme.primary,
                                                    fontWeight: FontWeight.w600,
                                                  )
                                                : null,
                                          ),
                                        if (phone != null && d.shopName != null)
                                          const TextSpan(text: ' • '),
                                        if (d.shopName != null) TextSpan(text: d.shopName),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        balanceText(l10n, summary.balance),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: balanceColor(scheme, summary.balance),
                        ),
                      ),
                      if (overdue && days != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _OverdueBadge(days: days),
                        ),
                    ],
                  ),
                ],
              ),
              if (days != null || summary.operationCount > 0) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (days != null)
                      _Info(icon: Icons.schedule_rounded, text: lastOperationText(l10n, days)),
                    if (summary.operationCount > 0)
                      _Info(icon: Icons.receipt_long_rounded, text: l10n.debtOperationsCount(summary.operationCount)),
                    if (summary.totalGiven > 0)
                      _Info(
                        icon: Icons.payments_rounded,
                        text: l10n.debtPaidShare((summary.paidShare * 100).round()),
                      ),
                  ],
                ),
              ],
              if (summary.totalGiven > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: summary.paidShare,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
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
