import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/widgets.dart';

/// A card heading (`card h2`) with an optional dim " · detail" and trailing widgets.
class CardHeading extends StatelessWidget {
  const CardHeading(this.title, {super.key, this.detail, this.trailing = const []});

  final String title;
  final String? detail;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: title,
                children: [
                  if (detail != null)
                    TextSpan(
                      text: ' · $detail',
                      style: TextStyle(color: context.palette.label3),
                    ),
                ],
              ),
              style: t.caption,
            ),
          ),
          for (final w in trailing) ...[const SizedBox(width: 8), w],
        ],
      ),
    );
  }
}

/// A caption between the parts of a card (`h4.sec` inside a card), flush with the card's text.
class CardCaption extends StatelessWidget {
  const CardCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 7),
    child: Text(text, style: context.textStyles.caption),
  );
}

/// Stat tiles two per row, each row as tall as its tallest tile (values may use smaller type).
class TilePairs extends StatelessWidget {
  const TilePairs({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

/// A muscle / histogram row (`.mrow`): name, a 74 px bar and a right-aligned value.
class MetricBarRow extends StatelessWidget {
  const MetricBarRow({
    super.key,
    required this.label,
    required this.value,
    this.fraction,
    this.color,
    this.bold = false,
  });

  final String label;
  final String value;

  /// Bar fill 0–1; null hides the bar.
  final double? fraction;

  /// Bar colour (default accent).
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = fraction;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: p.label, fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
          if (f != null) ...[
            const SizedBox(width: 10),
            Container(
              width: 74,
              height: 5,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(3)),
              child: FractionallySizedBox(
                widthFactor: f.clamp(0, 1).toDouble(),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: color ?? p.acc, borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52),
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: p.label2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small secondary text (`.small.dim` / `.muted.small`).
class NoteText extends StatelessWidget {
  const NoteText(this.text, {super.key, this.color, this.top = 8});

  final String text;

  /// Defaults to label-3.
  final Color? color;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: Text(text, style: context.textStyles.small.copyWith(color: color ?? context.palette.label3)),
  );
}

/// A big value with a caption under it (`.stat-v` + `.small.dim`).
class StatValue extends StatelessWidget {
  const StatValue({
    super.key,
    required this.value,
    required this.caption,
    this.color,
    this.align = TextAlign.left,
    this.fontSize,
  });

  final String value;
  final String caption;
  final Color? color;
  final TextAlign align;

  /// Overrides the 26 px stat size.
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    final cross = switch (align) {
      TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
      TextAlign.center => CrossAxisAlignment.center,
      _ => CrossAxisAlignment.start,
    };
    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          textAlign: align,
          style: t.statValue.copyWith(color: color, fontSize: fontSize),
        ),
        Text(
          caption,
          textAlign: align,
          style: t.small.copyWith(color: context.palette.label3),
        ),
      ],
    );
  }
}

/// A label/value line inside a card, separated by hairlines (the exercise "last sessions").
class HairlineRow extends StatelessWidget {
  const HairlineRow({super.key, required this.leading, required this.trailing, this.last = false});

  final String leading;
  final String trailing;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = context.textStyles.small;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: p.sep, width: .5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(leading, style: style),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                trailing,
                textAlign: TextAlign.right,
                style: style.copyWith(color: p.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps the chips of a [MuscleChip] list.
class ChipWrap extends StatelessWidget {
  const ChipWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: children);
}
