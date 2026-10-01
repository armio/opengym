import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_icons.dart';
import 'formatting.dart';
import 'pressable.dart';
import 'routine_icon.dart';
import 'sheets.dart';

/// The standard scrolling page body: 16 px gutters, content capped at 560 px and centred,
/// safe-area top padding and room at the bottom for the tab bar.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh, this.controller, this.bottomPadding});

  final List<Widget> children;

  /// Enables pull-to-refresh.
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  /// Defaults to [AppSpacing.bottomClearance].
  final double? bottomPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        media.padding.top + 8,
        AppSpacing.gutter,
        (bottomPadding ?? AppSpacing.bottomClearance) + media.padding.bottom,
      ),
      children: [
        for (final child in children)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
              child: child,
            ),
          ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, color: context.palette.acc, child: list);
  }
}

/// Screen header (`.hdr`): large title, optional subtitle, trailing actions aligned to the
/// bottom, and an optional leading back button.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.leading});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.largeTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: t.subtitle)],
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 12), a],
        ],
      ),
    );
  }
}

/// A card: `--surface`, radius 14, padding 16, margin-bottom 12.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.border,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// E.g. the accent outline of the start chooser's today card.
  final BoxBorder? border;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = Container(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: border,
      ),
      padding: padding,
      child: child,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: onTap == null ? body : Pressable(onTap: onTap, pressedScale: .99, child: body),
    );
  }
}

/// Card heading (`card h2`): 13 px label-2 with optional trailing widgets.
class CardTitle extends StatelessWidget {
  const CardTitle(this.text, {super.key, this.trailing = const []});

  final String text;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.textStyles.caption)),
        ...trailing,
      ],
    ),
  );
}

/// An inset grouped list (`Section`): caption, rounded body with hairlines between rows, footer.
class Section extends StatelessWidget {
  const Section({super.key, this.title, this.footer, required this.children, this.trailing});

  final String? title;
  final String? footer;
  final List<Widget> children;

  /// Widget at the right of the caption (e.g. a small "Nueva" button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final withIcons =
        children.isNotEmpty &&
        children.every(
          (c) => switch (c) {
            GroupedRow(hasIcon: true) => true,
            _ => false,
          },
        );
    final indent = withIcons ? 55.0 : 14.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: Text(title ?? '', style: t.caption)),
                  ?trailing,
                ],
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: ColoredBox(
              color: p.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) Divider(height: .5, thickness: .5, indent: indent, color: p.sep),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
              child: Text(footer!, style: t.caption),
            ),
        ],
      ),
    );
  }
}

/// A row of a [Section]; rows with an icon badge move the hairlines past the icon rail.
abstract interface class GroupedRow {
  bool get hasIcon;
}

/// Trailing accessory of a [ListRow].
enum RowAccessory { none, chevron, check }

/// A grouped-list row (`Row`/`.lrow`): optional icon badge, title and subtitle, trailing
/// control, value text and accessory. Tappable rows darken on press; [danger] titles are red.
class ListRow extends StatelessWidget implements GroupedRow {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconTint,
    this.leading,
    this.trailing,
    this.value,
    this.accessory = RowAccessory.none,
    this.onTap,
    this.danger = false,
  });

  final String title;
  final String? subtitle;

  /// [AppIcons] name shown in a 29 px badge tinted [iconTint] (default accent).
  final String? icon;
  final Color? iconTint;

  /// Custom leading widget (instead of [icon]).
  final Widget? leading;

  /// A control after the text (switch, segmented…).
  final Widget? trailing;

  /// Secondary value text (17 px label-2).
  final String? value;
  final RowAccessory accessory;
  final VoidCallback? onTap;
  final bool danger;

  @override
  bool get hasIcon => icon != null || leading != null;

  /// With a [value], the title keeps at most this share of the room it shares with the value
  /// (and any [trailing] control) when both are long.
  static const double _titleShare = .5;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final titleStyle = t.rowTitle.copyWith(color: danger ? p.red : p.label);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: titleStyle),
        if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: t.caption)],
      ],
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ] else if (icon != null) ...[
              IconBadge(icon: icon!, tint: iconTint),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: value == null
                  ? Row(
                      children: [
                        Expanded(child: text),
                        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                      ],
                    )
                  : LayoutBuilder(builder: (context, box) => _withValue(context, text, titleStyle, box.maxWidth)),
            ),
            if (accessory == RowAccessory.chevron) ...[
              const SizedBox(width: 6),
              AppIcon('chevronRight', size: 18, color: p.label3),
            ],
            if (accessory == RowAccessory.check) ...[
              const SizedBox(width: 6),
              AppIcon('check', size: 18, color: p.acc),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Pressable(onTap: onTap, pressedScale: 1, pressedColor: p.surface2, color: Colors.transparent, child: row);
  }

  /// Title, [trailing] and the right-aligned [value] in [width]. The value (`.lrow-v`,
  /// `flex: none`) takes what it needs; only when both are long does the title keep its natural
  /// width up to [_titleShare] of the room, and the value wraps to a second line, then ellipsizes.
  Widget _withValue(BuildContext context, Widget text, TextStyle titleStyle, double width) {
    final t = context.textStyles;
    final double valueMax;
    if (trailing != null) {
      valueMax = width * (1 - _titleShare) / 2;
    } else {
      final painter = TextPainter(
        text: TextSpan(text: title, style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final titleWidth = painter.width.ceilToDouble();
      painter.dispose();
      valueMax = width - 8 - math.min(titleWidth, width * _titleShare);
    }
    return Row(
      children: [
        Expanded(child: text),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.max(0, valueMax)),
          child: Text(
            value!,
            style: t.rowTitle.copyWith(color: context.palette.label2),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// One option of a [SelectRow].
class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.subtitle});

  final T value;
  final String label;
  final String? subtitle;
}

/// Replaces a `<select>`: a [ListRow] showing the current option's label; tapping it opens a
/// sheet listing every option with a check on the current one. Picking closes the sheet, then
/// calls [onChanged].
class SelectRow<T> extends StatelessWidget implements GroupedRow {
  const SelectRow({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.iconTint,
    this.sheetTitle,
  });

  final String title;
  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? icon;
  final Color? iconTint;
  final String? sheetTitle;

  @override
  bool get hasIcon => icon != null;

  @override
  Widget build(BuildContext context) {
    SelectOption<T>? current;
    for (final o in options) {
      if (o.value == value) current = o;
    }
    return ListRow(
      title: title,
      icon: icon,
      iconTint: iconTint,
      value: current?.label ?? '$value',
      accessory: RowAccessory.chevron,
      onTap: () async {
        final picked = await showAppSheet<SelectOption<T>>(
          context,
          title: sheetTitle ?? title,
          builder: (ctx) => Section(
            children: [
              for (final o in options)
                ListRow(
                  title: o.label,
                  subtitle: o.subtitle,
                  accessory: o.value == value ? RowAccessory.check : RowAccessory.none,
                  onTap: () => Navigator.of(ctx).pop(o),
                ),
            ],
          ),
        );
        if (picked != null) onChanged(picked.value);
      },
    );
  }
}

/// A list item (`.item`): 60 px min height on `--surface`, radius 14, leading thumb/badge,
/// title + subtitle, trailing widgets.
class ListItem extends StatelessWidget {
  const ListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing = const [],
    this.onTap,
    this.capitalizeTitle = false,
    this.accentBar = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> trailing;
  final VoidCallback? onTap;

  /// Title Case the title (dataset names arrive lowercase).
  final bool capitalizeTitle;

  /// A 3 px accent bar on the left edge (superset members).
  final bool accentBar;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(capitalizeTitle ? capitalizeWords(title) : title, style: t.itemTitle),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            for (final w in trailing) ...[const SizedBox(width: 8), w],
          ],
        ),
      ),
    );
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        border: accentBar ? Border(left: BorderSide(color: p.acc, width: 3)) : null,
      ),
      child: body,
    );
    return Pressable(
      onTap: onTap,
      pressedScale: 1,
      color: p.surface,
      pressedColor: onTap == null ? p.surface : p.surface2,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: decorated,
    );
  }
}

/// A vertical list of [ListItem]s with the 8 px gap of `.list`.
class ItemList extends StatelessWidget {
  const ItemList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 8), children[i]],
    ],
  );
}

/// Chevron used as a list item's trailing accessory.
class Chevron extends StatelessWidget {
  const Chevron({super.key, this.icon = 'chevronRight'});

  final String icon;

  @override
  Widget build(BuildContext context) => AppIcon(icon, size: 18, color: context.palette.label3);
}

/// A small inline tag (`.tag`); [accent] gives the accent-soft variant.
class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    super.key,
    this.icon,
    this.accent = false,
    this.color,
    this.background,
    this.capitalize = true,
  });

  final String text;
  final String? icon;
  final bool accent;
  final Color? color;
  final Color? background;
  final bool capitalize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = color ?? (accent ? p.acc : p.label2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? (accent ? p.accSoft : p.surface2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[AppIcon(icon!, size: 13, color: fg), if (text.isNotEmpty) const SizedBox(width: 4)],
          if (text.isNotEmpty)
            Text(capitalize ? capitalizeFirst(text) : text, style: context.textStyles.tag.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// A PR badge: trophy + text on yellow.
class PrBadge extends StatelessWidget {
  const PrBadge({super.key, this.text = 'PR'});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: p.yellowSoft, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon('trophy', size: 13, color: p.yellow),
          const SizedBox(width: 4),
          Text(text, style: context.textStyles.tag.copyWith(color: p.yellow)),
        ],
      ),
    );
  }
}

/// A filter chip (`.chip`).
class AppChip extends StatelessWidget {
  const AppChip(this.label, {super.key, this.selected = false, this.onTap, this.icon, this.capitalize = true});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? icon;
  final bool capitalize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.onAcc : p.label;
    return Pressable(
      onTap: onTap,
      pressedScale: .96,
      color: selected ? p.acc : p.surface,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[AppIcon(icon!, size: 13, color: fg), const SizedBox(width: 4)],
            Text(
              capitalize ? capitalizeFirst(label) : label,
              style: TextStyle(fontSize: 14, color: fg, fontWeight: selected ? FontWeight.w500 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of chips (`.chips`, gap 7).
class ChipsRow extends StatelessWidget {
  const ChipsRow({super.key, required this.children, this.padding = EdgeInsets.zero});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 7), children[i]],
      ],
    ),
  );
}

/// A stat tile (`.tiles .tile`): label row + big value.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.valueStyle});

  final String label;
  final String value;
  final String? icon;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(AppRadii.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[AppIcon(icon!, size: 14, color: p.label), const SizedBox(width: 5)],
              Expanded(
                child: Text(label, style: t.caption, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: valueStyle ?? t.statValue),
        ],
      ),
    );
  }
}

/// A two-column grid of [StatTile]s (gap 10).
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 10), rows[i]],
        ],
      ),
    );
  }
}

/// Empty state (`.empty`): icon above centred label-2 text.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon, this.action});

  final String message;

  /// [AppIcons] name.
  final String? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[AppIcon(icon!, size: 34, color: p.label2), const SizedBox(height: 12)],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45, color: p.label2),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A section caption outside grouped lists (`h4.sec`).
class SectionCaption extends StatelessWidget {
  const SectionCaption(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 7),
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.textStyles.caption)),
        ?trailing,
      ],
    ),
  );
}
