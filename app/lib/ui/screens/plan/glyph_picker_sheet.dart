import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/widgets.dart';

/// "Elige un icono" (specs/ui.md §4.10, §2.6): the 20 routine glyphs in four groups of five;
/// the current one is filled with the accent. Resolves to the picked icon key, or null.
Future<String?> showGlyphPicker(BuildContext context, String? current) => showAppSheet<String>(
  context,
  title: 'Elige un icono',
  builder: (ctx) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final group in glyphGroups)
        _GlyphGroupGrid(group: group, current: glyphOf(current), onPick: (key) => Navigator.of(ctx).pop(key)),
      const SizedBox(height: 4),
    ],
  ),
);

class _GlyphGroupGrid extends StatelessWidget {
  const _GlyphGroupGrid({required this.group, required this.current, required this.onPick});

  final GlyphGroup group;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 7),
          child: Text(group.label, style: context.textStyles.caption),
        ),
        Row(
          children: [
            for (var i = 0; i < group.items.length; i++) ...[
              if (i > 0) const SizedBox(width: 9),
              Expanded(
                child: _GlyphCell(glyph: group.items[i], selected: group.items[i] == current, onTap: onPick),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

/// A square cell (radius 13) with the glyph at 24 px; accent-filled when [selected].
class _GlyphCell extends StatelessWidget {
  const _GlyphCell({required this.glyph, required this.selected, required this.onTap});

  final String glyph;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: () => onTap(glyph),
        pressedScale: .92,
        color: selected ? p.acc : p.surface,
        borderRadius: BorderRadius.circular(13),
        semanticLabel: glyph,
        child: AspectRatio(
          aspectRatio: 1,
          child: Center(child: AppIcon(glyph, size: 24, color: selected ? p.onAcc : p.label)),
        ),
      ),
    );
  }
}
