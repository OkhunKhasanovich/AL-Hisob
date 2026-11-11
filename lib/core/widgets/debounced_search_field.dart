import 'dart:async';

import 'package:flutter/material.dart';

import 'glass.dart';

/// Строка поиска: изменения уходят в [onChanged] с задержкой, чтобы не
/// пересчитывать выдачу на каждую букву; кнопка «очистить» реагирует сразу.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({
    super.key,
    required this.hintText,
    required this.clearTooltip,
    required this.onChanged,
    this.initialText = '',
    this.debounce = const Duration(milliseconds: 250),
    this.trailingActions = const [],
    this.compact = false,
  });

  final String hintText;
  final String clearTooltip;
  final String initialText;
  final Duration debounce;
  final ValueChanged<String> onChanged;

  /// Кнопки в конце поля (после «очистить»), например фильтры.
  final List<Widget> trailingActions;

  /// Низкое поле (44 вместо 56).
  final bool compact;

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  Timer? _timer;

  void _onChanged(String text) {
    setState(() {});
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      if (mounted) widget.onChanged(text);
    });
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SearchBar(
      controller: _controller,
      hintText: widget.hintText,
      elevation: const WidgetStatePropertyAll(0),
      // Чёрное полупрозрачное стекло, как карточки: фон приложения просвечивает.
      backgroundColor: WidgetStatePropertyAll(glassBase(theme.brightness)),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(
        BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.30)),
      ),
      constraints: widget.compact ? const BoxConstraints(minHeight: 44, maxHeight: 44) : null,
      padding: widget.compact
          ? const WidgetStatePropertyAll(EdgeInsets.only(left: 14, right: 4))
          : null,
      leading: const Icon(Icons.search_rounded),
      trailing: [
        if (_controller.text.isNotEmpty)
          IconButton(
            tooltip: widget.clearTooltip,
            icon: const Icon(Icons.close_rounded),
            onPressed: _clear,
          ),
        ...widget.trailingActions,
      ],
      textInputAction: TextInputAction.search,
      onChanged: _onChanged,
    );
  }
}
