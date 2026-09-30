import 'package:flutter/material.dart';

import '../theme.dart';

/// Tap target with the app's press feedback: a slight scale ("presses acknowledge, nothing
/// bounces") and an optional pressed background. Used by buttons, rows and cells.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = .975,
    this.color,
    this.pressedColor,
    this.borderRadius,
    this.semanticLabel,
    this.button = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale while pressed (buttons .975, icon buttons .92, checks .9).
  final double pressedScale;

  /// Background at rest.
  final Color? color;

  /// Background while pressed (defaults to [color]).
  final Color? pressedColor;
  final BorderRadius? borderRadius;
  final String? semanticLabel;
  final bool button;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bg = _down ? (widget.pressedColor ?? widget.color) : widget.color;
    Widget child = widget.child;
    if (bg != null || widget.borderRadius != null) {
      child = AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.ease,
        decoration: BoxDecoration(color: bg, borderRadius: widget.borderRadius),
        clipBehavior: widget.borderRadius == null ? Clip.none : Clip.antiAlias,
        child: child,
      );
    }
    return Semantics(
      button: widget.button && _enabled,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _set(true) : null,
        onTapUp: _enabled ? (_) => _set(false) : null,
        onTapCancel: _enabled ? () => _set(false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down && !reduceMotion ? widget.pressedScale : 1,
          duration: AppMotion.fast,
          curve: AppMotion.ease,
          child: child,
        ),
      ),
    );
  }
}
