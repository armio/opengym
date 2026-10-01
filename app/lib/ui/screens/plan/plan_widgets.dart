import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/widgets.dart';

/// A single grouped-list body (`.sect-b`: `--surface`, radius 14, clipped) without the
/// caption and bottom margin of a [Section].
class GroupedBox extends StatelessWidget {
  const GroupedBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadii.card),
    child: ColoredBox(color: context.palette.surface, child: child),
  );
}

/// Small dim text (`.small.dim`), with an optional leading icon.
class DimNote extends StatelessWidget {
  const DimNote(this.text, {super.key, this.icon, this.textAlign = TextAlign.start});

  final String text;
  final String? icon;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = Text(
      text,
      textAlign: textAlign,
      style: context.textStyles.small.copyWith(color: p.label3),
    );
    if (icon == null) return label;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AppIcon(icon!, size: 13, color: p.label3),
        ),
        const SizedBox(width: 5),
        Expanded(child: label),
      ],
    );
  }
}

/// A routine's name on an accent tag with its glyph (the week schedule's assignment). The name
/// is cut with an ellipsis when the tag runs out of room.
class RoutineTag extends StatelessWidget {
  const RoutineTag({super.key, required this.name, required this.emoji});

  final String name;

  /// The routine's `emoji` field.
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: p.accSoft, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoutineIcon(emoji, size: 13, color: p.acc),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.tag.copyWith(color: p.acc),
            ),
          ),
        ],
      ),
    );
  }
}
