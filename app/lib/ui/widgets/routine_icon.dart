import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_icons.dart';

/// The default routine glyph.
const defaultGlyph = 'figureStrength';

/// A group of the glyph picker (specs/library.md §6).
class GlyphGroup {
  const GlyphGroup(this.label, this.items);

  /// Spanish group name.
  final String label;
  final List<String> items;
}

/// The glyph picker's groups, 4 × 5 keys, in order.
const glyphGroups = [
  GlyphGroup('Fuerza', ['figureStrength', 'arm', 'abs', 'legs', 'pullup']),
  GlyphGroup('Equipo', ['dumbbell', 'barbell', 'kettlebell', 'plate', 'machine']),
  GlyphGroup('Cardio', ['figureRun', 'bike', 'swim', 'boxing', 'timer']),
  GlyphGroup('Recuperación', ['stretch', 'moon', 'heart', 'flame', 'bolt']),
];

/// The 20 glyphs the picker offers (and Claude is told to choose from).
final List<String> glyphKeys = [for (final g in glyphGroups) ...g.items];

/// Legacy literal emoji stored in `Routine.emoji` before icon keys existed.
const Map<String, String> _legacyGlyphs = {
  '💪': 'arm', '🦾': 'arm', '🫸': 'figureStrength', '🫷': 'pullup', //
  '🏋️': 'dumbbell', '🏋': 'dumbbell', '🏋️‍♀️': 'dumbbell',
  '🦵': 'legs', '🍑': 'legs',
  '🔥': 'flame', '⚡': 'bolt', '💥': 'bolt', '🧨': 'bolt', '😤': 'flame',
  '🏃': 'figureRun', '🏃‍♀️': 'figureRun', '🚴': 'bike', '🏊': 'swim',
  '🤸': 'stretch', '🧘': 'stretch', '🧘‍♀️': 'stretch',
  '🥊': 'boxing', '🧗': 'pullup', '⛰️': 'figureRun', '🏔️': 'figureRun', '🚀': 'bolt',
  '🎯': 'target', '🏆': 'trophy', '🥇': 'medal', '⭐': 'star', '🌟': 'star',
  '👑': 'crown', '🛡️': 'shield', '⚔️': 'shield', '❤️‍🔥': 'heart',
  '🦍': 'kettlebell', '🐂': 'barbell', '🐻': 'kettlebell', '🦁': 'boxing',
  '🐺': 'figureRun', '🦈': 'swim', '🤖': 'machine',
};

/// `glyphOf(v)`: the icon key for a routine's `emoji` field. Any icon name passes through,
/// legacy emoji are mapped (also after stripping U+FE0F / U+200D), anything else is the default.
String glyphOf(String? value) {
  if (value == null || value.isEmpty) return defaultGlyph;
  if (AppIcons.byName.containsKey(value)) return value;
  final legacy = _legacyGlyphs[value];
  if (legacy != null) return legacy;
  final base = value.runes.where((r) => r != 0xFE0F && r != 0x200D);
  if (base.isEmpty) return defaultGlyph;
  return _legacyGlyphs[String.fromCharCode(base.first)] ?? defaultGlyph;
}

/// A routine's glyph as an icon (no badge).
class RoutineIcon extends StatelessWidget {
  const RoutineIcon(this.emoji, {super.key, this.size = 18, this.color});

  /// The routine's `emoji` field (icon key or legacy emoji).
  final String? emoji;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => AppIcon(glyphOf(emoji), size: size, color: color);
}

/// Size presets of [IconBadge] (specs/ui.md §2.6).
enum BadgeSize {
  /// 29 px, radius 7, icon 18 — list rows.
  row(29, 7, 18),

  /// 34 px, radius 8, icon 19 — workout rows.
  medium(34, 8, 19),

  /// 38 px, radius 9, icon 22 — the start chooser's today card.
  large(38, 9, 22);

  const BadgeSize(this.box, this.radius, this.icon);

  final double box;
  final double radius;
  final double icon;
}

/// A white icon on a rounded tinted square — the `lrow-i` badge. [tint] defaults to the accent;
/// use `context.palette.surface3` for neutral badges (rest, new routine).
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.tint, this.foreground, this.size = BadgeSize.row});

  /// Builds a badge for a routine's `emoji` field.
  factory IconBadge.routine(
    String? emoji, {
    Key? key,
    Color? tint,
    Color? foreground,
    BadgeSize size = BadgeSize.row,
  }) => IconBadge(key: key, icon: glyphOf(emoji), tint: tint, foreground: foreground, size: size);

  /// An [AppIcons] name.
  final String icon;
  final Color? tint;
  final Color? foreground;
  final BadgeSize size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = tint ?? p.acc;
    return Container(
      width: size.box,
      height: size.box,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size.radius)),
      alignment: Alignment.center,
      child: AppIcon(icon, size: size.icon, color: foreground ?? Colors.white),
    );
  }
}
