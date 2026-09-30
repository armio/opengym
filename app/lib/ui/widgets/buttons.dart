import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_icons.dart';
import 'pressable.dart';

/// Button variants of specs/ui.md §2.8. [plain] and [ghost] look the same (accent text, no
/// fill) — the original's default `Button` is `plain`.
enum ButtonVariant { plain, primary, tinted, danger, ghost }

/// Button sizes: [regular] fills the width (17 px), [sm] and [xs] hug their content.
enum ButtonSize { regular, sm, xs }

/// The app button.
///
/// ```dart
/// AppButton('Guardar', variant: ButtonVariant.primary, onPressed: save)
/// AppButton('Registrar', icon: 'plus', size: ButtonSize.sm, onPressed: log)
/// ```
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.variant = ButtonVariant.plain,
    this.size = ButtonSize.regular,
    this.icon,
    this.trailingIcon,
    this.dim = false,
    this.busy = false,
    this.expand,
    this.foreground,
  });

  final String label;

  /// Null disables the button (opacity .32).
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;

  /// Leading [AppIcons] name.
  final String? icon;

  /// Trailing [AppIcons] name.
  final String? trailingIcon;

  /// Ghost/plain only: label-3 text (the original's `className="dim"`).
  final bool dim;

  /// Shows a spinner instead of the leading icon and ignores taps.
  final bool busy;

  /// Full width; defaults to true for [ButtonSize.regular].
  final bool? expand;

  /// Overrides the text/icon colour.
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final enabled = onPressed != null && !busy;
    final (Color? bg, Color pressedBg, Color fg, FontWeight weight) = switch (variant) {
      ButtonVariant.primary => (p.acc, p.acc2, p.onAcc, FontWeight.w600),
      ButtonVariant.tinted => (p.accSoft, p.accSoft, p.acc, FontWeight.w600),
      ButtonVariant.danger => (p.redSoft, p.redSoft, p.red, FontWeight.w600),
      ButtonVariant.plain || ButtonVariant.ghost => (null, p.surface2, dim ? p.label3 : p.acc, FontWeight.w400),
    };
    final color = foreground ?? fg;
    final (EdgeInsets padding, double fontSize, double radius, double iconSize) = switch (size) {
      ButtonSize.regular => (const EdgeInsets.symmetric(horizontal: 18, vertical: 14), 17.0, AppRadii.r, 19.0),
      ButtonSize.sm => (const EdgeInsets.symmetric(horizontal: 14, vertical: 8), 15.0, AppRadii.sm, 16.0),
      ButtonSize.xs => (const EdgeInsets.symmetric(horizontal: 10, vertical: 5), 13.0, 7.0, 14.0),
    };
    final fill = expand ?? size == ButtonSize.regular;
    final leading = busy
        ? SizedBox.square(
            dimension: iconSize - 2,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        : icon == null
        ? null
        : AppIcon(icon!, size: iconSize, color: color);
    final content = Row(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 7)],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: t.button.copyWith(fontSize: fontSize, fontWeight: weight, color: color),
          ),
        ),
        if (trailingIcon != null) ...[const SizedBox(width: 7), AppIcon(trailingIcon!, size: iconSize, color: color)],
      ],
    );
    return Opacity(
      opacity: enabled || busy ? 1 : .32,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Pressable(
          onTap: enabled ? onPressed : null,
          color: bg,
          pressedColor: pressedBg,
          borderRadius: BorderRadius.circular(radius),
          semanticLabel: label,
          child: Padding(padding: padding, child: content),
        ),
      ),
    );
  }
}

/// A round icon button (`.iconbtn`): 36 px circle on `--surface`; [selected] tints it
/// (`.on-ss`: accent-soft background, accent icon).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.selected = false,
    this.size = 36,
    this.iconSize = 18,
    this.color,
    this.background,
    this.borderRadius,
  });

  /// [AppIcons] name.
  final String icon;
  final VoidCallback? onPressed;

  /// Accessibility label (and long-press tooltip).
  final String? tooltip;
  final bool selected;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? background;

  /// Null = circle.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = borderRadius ?? BorderRadius.circular(size / 2);
    final button = Opacity(
      opacity: onPressed == null ? .32 : 1,
      child: Pressable(
        onTap: onPressed,
        pressedScale: .92,
        color: background ?? (selected ? p.accSoft : p.surface),
        pressedColor: p.surface2,
        borderRadius: radius,
        semanticLabel: tooltip,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: AppIcon(icon, size: iconSize, color: color ?? (selected ? p.acc : p.label)),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
