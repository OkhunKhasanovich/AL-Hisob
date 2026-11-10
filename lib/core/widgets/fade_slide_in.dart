import 'package:flutter/material.dart';

/// Плавное появление (fade + сдвиг снизу) с задержкой. Без таймеров:
/// задержка задана участком кривой одного контроллера.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 450),
    this.enabled = true,
  });

  /// `false` — показать сразу, без анимации (проверяется при создании виджета).
  final bool enabled;

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _curve = const AlwaysStoppedAnimation(1);
      return;
    }
    final total = widget.delay + widget.duration;
    final controller = _controller = AnimationController(vsync: this, duration: total)..forward();
    _curve = CurvedAnimation(
      parent: controller,
      curve: Interval(
        widget.delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
