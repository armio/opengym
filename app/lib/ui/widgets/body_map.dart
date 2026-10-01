import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../engine/muscles.dart' show inertBodyParts, muscleNames, muscles;
import '../theme.dart';
import 'body_map_paths.dart';

/// Front and back views of a body, each muscle shaded by how hard it was worked
/// (specs/ui.md §7.3): the silhouette first, then the 18 muscles filled with the heat ramp of
/// their level (0–4, e.g. from the engine's `levelsOf(loadOfRoutine(…))`), every part outlined
/// in the surface colour so neighbouring muscles stay apart.
///
/// * [figure] is `settings.body` (`'male'` | `'female'`; anything else draws the male figure).
/// * [compact] caps the height lower (≤ 180 px instead of min(46 % of the screen, 340 px)).
/// * [highlight] muscles get a thick outline in the label colour (the selected muscle).
/// * [onMuscle] makes the map tappable: a tap on a muscle reports its slug.
class BodyMap extends StatelessWidget {
  const BodyMap({
    super.key,
    required this.levels,
    this.figure = 'male',
    this.compact = false,
    this.highlight,
    this.onMuscle,
  });

  /// Muscle slug → shade 0–4; missing muscles are 0.
  final Map<String, int> levels;
  final String figure;
  final bool compact;
  final Set<String>? highlight;
  final ValueChanged<String>? onMuscle;

  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final geometry = bodyGeometry[figure] ?? bodyGeometry['male']!;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = compact ? 180.0 : math.min(340.0, screenHeight * .46);
    final vb = geometry.front.viewBox;
    return LayoutBuilder(
      builder: (context, box) {
        final viewWidth = (box.maxWidth - _gap) / 2;
        final height = math.min(maxHeight, viewWidth * vb[3] / vb[2]);
        return Semantics(
          image: true,
          label: _semanticLabel(),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                Expanded(child: _view(context, figure, geometry.front, front: true)),
                const SizedBox(width: _gap),
                Expanded(child: _view(context, figure, geometry.back, front: false)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _view(BuildContext context, String figure, BodyViewGeometry geometry, {required bool front}) {
    final p = context.palette;
    final painter = _BodyViewPainter(
      view: _ParsedView.of(figure, front, geometry),
      levels: levels,
      highlight: highlight ?? const {},
      colors: _BodyColors(
        fills: [for (var l = 0; l <= 4; l++) p.muscleFill(l)],
        silhouette: p.silhouette,
        outline: p.surface,
        selected: p.label,
      ),
    );
    final paint = CustomPaint(painter: painter, size: Size.infinite);
    final tap = onMuscle;
    if (tap == null) return paint;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final slug = painter.muscleAt(d.localPosition, box.biggest);
          if (slug != null) tap(slug);
        },
        child: paint,
      ),
    );
  }

  String _semanticLabel() {
    final worked = [
      for (final m in muscles)
        if ((levels[m] ?? 0) > 0) muscleNames[m]!,
    ];
    return worked.isEmpty ? 'Mapa muscular: nada trabajado' : 'Mapa muscular: ${worked.join(', ')}';
  }
}

/// The heat-ramp key under a body map: "Menos ▢▢▢▢▢ Más" (the activity heatmap's cells).
class BodyMapLegend extends StatelessWidget {
  const BodyMapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(fontSize: 11, color: p.label3);
    Widget cell(int level) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: p.heatCell(level), borderRadius: BorderRadius.circular(3)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Menos', style: style),
          for (var l = 0; l <= 4; l++) ...[const SizedBox(width: 4), cell(l)],
          const SizedBox(width: 4),
          Text('Más', style: style),
        ],
      ),
    );
  }
}

/// A muscle name pill (`.mchip`); [missed] is the orange "not trained" variant.
class MuscleChip extends StatelessWidget {
  const MuscleChip(this.muscle, {super.key, this.missed = false});

  /// Muscle slug (e.g. `'upper-back'`); shown with its Spanish name.
  final String muscle;
  final bool missed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: missed ? p.orangeSoft : p.surface2, borderRadius: BorderRadius.circular(99)),
      child: Text(muscleNames[muscle] ?? muscle, style: TextStyle(fontSize: 12, color: missed ? p.orange : p.label2)),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Painting.

@immutable
class _BodyColors {
  const _BodyColors({required this.fills, required this.silhouette, required this.outline, required this.selected});

  /// Muscle fill per level 0–4.
  final List<Color> fills;
  final Color silhouette;
  final Color outline;
  final Color selected;

  @override
  bool operator ==(Object other) =>
      other is _BodyColors &&
      listEquals(other.fills, fills) &&
      other.silhouette == silhouette &&
      other.outline == outline &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(Object.hashAll(fills), silhouette, outline, selected);
}

/// One view's geometry parsed into [Path]s (in viewBox coordinates), cached for the app's life.
class _ParsedView {
  _ParsedView(BodyViewGeometry geometry)
    : viewBox = Rect.fromLTWH(geometry.viewBox[0], geometry.viewBox[1], geometry.viewBox[2], geometry.viewBox[3]),
      inert = [for (final slug in inertBodyParts) ...?geometry.parts[slug]?.map(parseSvgPathData)],
      musclePaths = {
        for (final slug in muscles)
          if (geometry.parts[slug] case final paths?) slug: [for (final d in paths) parseSvgPathData(d)],
      };

  static final _cache = <String, _ParsedView>{};

  static _ParsedView of(String figure, bool front, BodyViewGeometry geometry) =>
      _cache.putIfAbsent('$figure/${front ? 'front' : 'back'}', () => _ParsedView(geometry));

  final Rect viewBox;
  final List<Path> inert;

  /// Muscle slug → its paths, in the body order of the engine's `muscles` (the paint order).
  final Map<String, List<Path>> musclePaths;
}

class _BodyViewPainter extends CustomPainter {
  _BodyViewPainter({required this.view, required this.levels, required this.highlight, required this.colors});

  final _ParsedView view;
  final Map<String, int> levels;
  final Set<String> highlight;
  final _BodyColors colors;

  /// Stroke widths in viewBox units, as the original's CSS applies them inside the SVG.
  static const _outlineWidth = 2.5;
  static const _selectedWidth = 7.0;

  /// Scale and offset that fit the viewBox into [size], centred (`xMidYMid meet`).
  Matrix4 _transform(Size size) {
    final vb = view.viewBox;
    final scale = math.min(size.width / vb.width, size.height / vb.height);
    final dx = (size.width - vb.width * scale) / 2 - vb.left * scale;
    final dy = (size.height - vb.height * scale) / 2 - vb.top * scale;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.transform(_transform(size).storage);
    final fill = Paint()..style = PaintingStyle.fill;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _outlineWidth
      ..strokeJoin = StrokeJoin.round
      ..color = colors.outline;
    final selected = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _selectedWidth
      ..strokeJoin = StrokeJoin.round
      ..color = colors.selected;

    fill.color = colors.silhouette;
    for (final path in view.inert) {
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, outline);
    }
    view.musclePaths.forEach((slug, paths) {
      fill.color = colors.fills[(levels[slug] ?? 0).clamp(0, 4)];
      final isSelected = highlight.contains(slug);
      for (final path in paths) {
        canvas
          ..drawPath(path, fill)
          ..drawPath(path, isSelected ? selected : outline);
      }
    });
    canvas.restore();
  }

  /// The muscle under [position] (widget coordinates), topmost first; null when none.
  String? muscleAt(Offset position, Size size) {
    if (size.isEmpty) return null;
    final inverse = Matrix4.tryInvert(_transform(size));
    if (inverse == null) return null;
    final point = MatrixUtils.transformPoint(inverse, position);
    for (final entry in view.musclePaths.entries.toList().reversed) {
      if (entry.value.any((path) => path.contains(point))) return entry.key;
    }
    return null;
  }

  @override
  bool shouldRepaint(_BodyViewPainter old) =>
      old.view != view ||
      !mapEquals(old.levels, levels) ||
      !setEquals(old.highlight, highlight) ||
      old.colors != colors;
}

// ---------------------------------------------------------------------------------------------
// SVG path data.

/// Parses SVG path data — every command, absolute and relative, arcs included, with the
/// minified forms the geometry uses (`.5.5`, `-1-2`, arc flags written together as `01`).
/// Malformed input stops parsing at the first bad token and keeps what was read.
@visibleForTesting
Path parseSvgPathData(String d) {
  final path = Path();
  final s = _PathScanner(d);
  var cx = 0.0, cy = 0.0; // current point
  var sx = 0.0, sy = 0.0; // start of the subpath
  // Control point reflected by S/s (cubic) and T/t (quadratic); null after other commands.
  Offset? lastCubic, lastQuad;
  String? command;

  while (true) {
    s.skipSeparators();
    if (s.done) break;
    if (s.atCommand) {
      command = s.readCommand();
    } else if (command == null || !s.atNumber) {
      break;
    }
    final c = command;
    final relative = c == c.toLowerCase();
    final ox = relative ? cx : 0.0, oy = relative ? cy : 0.0;
    Offset? nextCubic, nextQuad;
    try {
      switch (c.toLowerCase()) {
        case 'z':
          path.close();
          cx = sx;
          cy = sy;
          // `z` takes no parameters; a number after it cannot continue the command.
          command = null;
        case 'm':
          cx = ox + s.number();
          cy = oy + s.number();
          path.moveTo(cx, cy);
          sx = cx;
          sy = cy;
          // Extra pairs after a moveto are linetos.
          command = relative ? 'l' : 'L';
        case 'l':
          cx = ox + s.number();
          cy = oy + s.number();
          path.lineTo(cx, cy);
        case 'h':
          cx = ox + s.number();
          path.lineTo(cx, cy);
        case 'v':
          cy = oy + s.number();
          path.lineTo(cx, cy);
        case 'c':
          final x1 = ox + s.number(), y1 = oy + s.number();
          final x2 = ox + s.number(), y2 = oy + s.number();
          cx = ox + s.number();
          cy = oy + s.number();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
          nextCubic = Offset(x2, y2);
        case 's':
          final x1 = lastCubic == null ? cx : 2 * cx - lastCubic.dx;
          final y1 = lastCubic == null ? cy : 2 * cy - lastCubic.dy;
          final x2 = ox + s.number(), y2 = oy + s.number();
          cx = ox + s.number();
          cy = oy + s.number();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
          nextCubic = Offset(x2, y2);
        case 'q':
          final x1 = ox + s.number(), y1 = oy + s.number();
          cx = ox + s.number();
          cy = oy + s.number();
          path.quadraticBezierTo(x1, y1, cx, cy);
          nextQuad = Offset(x1, y1);
        case 't':
          final x1 = lastQuad == null ? cx : 2 * cx - lastQuad.dx;
          final y1 = lastQuad == null ? cy : 2 * cy - lastQuad.dy;
          cx = ox + s.number();
          cy = oy + s.number();
          path.quadraticBezierTo(x1, y1, cx, cy);
          nextQuad = Offset(x1, y1);
        case 'a':
          final rx = s.number().abs(), ry = s.number().abs();
          final rotation = s.number();
          final largeArc = s.flag(), sweep = s.flag();
          cx = ox + s.number();
          cy = oy + s.number();
          if (rx == 0 || ry == 0) {
            path.lineTo(cx, cy);
          } else {
            // SVG's positive-angle sweep is clockwise on screen (y grows downwards).
            path.arcToPoint(
              Offset(cx, cy),
              radius: Radius.elliptical(rx, ry),
              rotation: rotation,
              largeArc: largeArc,
              clockwise: sweep,
            );
          }
        default:
          return path;
      }
    } on FormatException {
      break;
    }
    lastCubic = nextCubic;
    lastQuad = nextQuad;
  }
  return path;
}

/// Reads the tokens of SVG path data.
class _PathScanner {
  _PathScanner(this.source);

  final String source;
  int _i = 0;

  static final _numberPattern = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
  static const _commands = 'MmLlHhVvCcSsQqTtAaZz';

  bool get done => _i >= source.length;

  bool get atCommand => !done && _commands.contains(source[_i]);

  bool get atNumber => !done && _numberPattern.matchAsPrefix(source, _i) != null;

  void skipSeparators() {
    while (!done) {
      final ch = source[_i];
      if (ch != ' ' && ch != ',' && ch != '\n' && ch != '\t' && ch != '\r') return;
      _i++;
    }
  }

  String readCommand() => source[_i++];

  double number() {
    skipSeparators();
    final match = done ? null : _numberPattern.matchAsPrefix(source, _i);
    if (match == null) throw FormatException('Expected a number', source, _i);
    _i = match.end;
    return double.parse(match[0]!);
  }

  /// An arc flag: a single `0` or `1`, which may run straight into the next token.
  bool flag() {
    skipSeparators();
    if (done || (source[_i] != '0' && source[_i] != '1')) throw FormatException('Expected a flag', source, _i);
    return source[_i++] == '1';
  }
}
