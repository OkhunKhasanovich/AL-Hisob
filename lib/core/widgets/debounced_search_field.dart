import 'dart:async';

import 'package:flutter/material.dart';

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
  });

  final String hintText;
  final String clearTooltip;
  final String initialText;
  final Duration debounce;
  final ValueChanged<String> onChanged;

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
    return SearchBar(
      controller: _controller,
      hintText: widget.hintText,
      elevation: const WidgetStatePropertyAll(0),
      leading: const Icon(Icons.search_rounded),
      trailing: [
        if (_controller.text.isNotEmpty)
          IconButton(
            tooltip: widget.clearTooltip,
            icon: const Icon(Icons.close_rounded),
            onPressed: _clear,
          ),
      ],
      textInputAction: TextInputAction.search,
      onChanged: _onChanged,
    );
  }
}
