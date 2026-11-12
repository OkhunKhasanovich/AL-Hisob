import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../update/presentation/update_controller.dart';
import 'floating_nav_bar.dart';
import '../update/presentation/update_dialog.dart';

/// Каркас с нижней навигацией. Вкладки сохраняют своё состояние
/// (StatefulShellRoute), а переключение идёт с плавным fade.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();

  /// Контейнер веток: все вкладки живут в Stack, активная плавно проявляется.
  static Widget branchContainer(
    BuildContext context,
    StatefulNavigationShell shell,
    List<Widget> children,
  ) => Stack(
    children: [
      for (var i = 0; i < children.length; i++)
        AnimatedOpacity(
          opacity: i == shell.currentIndex ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: IgnorePointer(
            ignoring: i != shell.currentIndex,
            child: TickerMode(enabled: i == shell.currentIndex, child: children[i]),
          ),
        ),
    ],
  );
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    // Проверка обновления при запуске (в сборках для разработки ничего не делает).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updateControllerProvider.notifier).checkOnStartup();
    });
  }

  Future<void> _showUpdate() async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    await showUpdateDialog(context);
    _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final l10n = context.l10n;

    ref.listen(updateControllerProvider, (previous, next) {
      // Предложение обновления и «загружено, можно устанавливать».
      final offer =
          (next.phase == UpdatePhase.available && previous?.phase != UpdatePhase.available) ||
          (next.phase == UpdatePhase.ready && previous?.phase != UpdatePhase.ready) ||
          // Фоновая загрузка не удалась — сообщаем, а не молчим.
          (next.phase == UpdatePhase.error && previous?.phase == UpdatePhase.downloading);
      if (offer) _showUpdate();
    });

    return Scaffold(
      body: navigationShell,
      // Без подложки под панелью: страницы заходят под неё, вокруг «таблетки» виден их фон.
      extendBody: true,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DownloadStrip(),
          FloatingNavBar(
            selectedIndex: navigationShell.currentIndex,
            onSelected: (index) {
              HapticFeedback.selectionClick();
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
            items: [
              FloatingNavItem(
                icon: Icons.menu_book_outlined,
                selectedIcon: Icons.menu_book_rounded,
                label: l10n.tabDebts,
              ),
              FloatingNavItem(
                icon: Icons.local_shipping_outlined,
                selectedIcon: Icons.local_shipping_rounded,
                label: l10n.tabOrders,
              ),
              FloatingNavItem(
                icon: Icons.inventory_2_outlined,
                selectedIcon: Icons.inventory_2_rounded,
                label: l10n.tabCatalog,
              ),
              FloatingNavItem(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: l10n.tabMore,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Тонкая полоса над вкладками: обновление скачивается в фоне, пользоваться приложением можно.
class _DownloadStrip extends ConsumerWidget {
  const _DownloadStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final downloading = state.phase == UpdatePhase.downloading;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: !downloading
          ? const SizedBox(width: double.infinity)
          : Material(
              key: const ValueKey('download-strip'),
              color: scheme.surfaceContainerHigh,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: state.progress == 0 ? null : state.progress,
                    minHeight: 2,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        Icon(
                          state.retry > 0 ? Icons.wifi_off_rounded : Icons.downloading_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusText(context, state),
                            maxLines: state.retry > 0 ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.updateOpenInBrowser,
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: const Icon(Icons.open_in_browser_rounded),
                          onPressed: ref.read(updateControllerProvider.notifier).openInBrowser,
                        ),
                        TextButton(
                          onPressed: ref.read(updateControllerProvider.notifier).cancelDownload,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 32),
                          ),
                          child: Text(context.l10n.updateCancel),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

String _statusText(BuildContext context, UpdateState state) {
  final l10n = context.l10n;
  if (state.retry > 0) {
    final reason = state.retryReason;
    final text = l10n.updateReconnecting(state.retry);
    return reason == null ? text : '$text\n$reason';
  }
  final percent = (state.progress * 100).round();
  final total = state.totalBytes;
  if (total == null || total <= 0) return l10n.updateDownloading(percent);
  final text = l10n.updateDownloadingBytes(
    percent,
    _megabytes(state.receivedBytes),
    _megabytes(total),
  );
  final bps = state.bytesPerSecond;
  if (bps <= 0) return text;
  final speed = bps >= 1024 * 1024
      ? '${(bps / (1024 * 1024)).toStringAsFixed(1)} ${l10n.unitMbPerSec}'
      : '${(bps / 1024).round()} ${l10n.unitKbPerSec}';
  return '$text · $speed';
}
