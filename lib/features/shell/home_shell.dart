import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../update/presentation/update_controller.dart';
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
  ) =>
      Stack(
        children: [
          for (var i = 0; i < children.length; i++)
            AnimatedOpacity(
              opacity: i == shell.currentIndex ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: IgnorePointer(
                ignoring: i != shell.currentIndex,
                child: TickerMode(
                  enabled: i == shell.currentIndex,
                  child: children[i],
                ),
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
      if (next.phase == UpdatePhase.available && previous?.phase != UpdatePhase.available) {
        _showUpdate();
      }
    });

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: [
          _destination(Icons.menu_book_outlined, Icons.menu_book_rounded, l10n.tabDebts),
          _destination(Icons.local_shipping_outlined, Icons.local_shipping_rounded, l10n.tabOrders),
          _destination(Icons.inventory_2_outlined, Icons.inventory_2_rounded, l10n.tabCatalog),
          _destination(Icons.more_horiz_rounded, Icons.more_horiz_rounded, l10n.tabMore),
        ],
      ),
    );
  }

  NavigationDestination _destination(IconData icon, IconData selected, String label) =>
      NavigationDestination(
        icon: Icon(icon),
        selectedIcon: Icon(selected),
        label: label,
      );
}
