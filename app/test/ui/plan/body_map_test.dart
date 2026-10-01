import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/ui/theme.dart';
import 'package:opengym/ui/widgets/body_map_paths.dart';
import 'package:opengym/ui/widgets/widgets.dart';

void main() {
  group('parseSvgPathData', () {
    test('absolute and relative lines, close', () {
      final bounds = parseSvgPathData('M0 0h10v10h-10z').getBounds();
      expect(bounds, const Rect.fromLTWH(0, 0, 10, 10));
      expect(parseSvgPathData('m5 5 10 0 0 10z').getBounds(), const Rect.fromLTWH(5, 5, 10, 10));
    });

    test('minified numbers and arc flags written together', () {
      expect(parseSvgPathData('M.5.5L10.5-9.5').getBounds(), const Rect.fromLTRB(.5, -9.5, 10.5, .5));
      final arc = parseSvgPathData('M0 0a5 5 0 0110 0').getBounds();
      expect(arc.width, closeTo(10, .01));
      expect(arc.height, closeTo(5, .01));
    });

    test('curves and their reflections', () {
      final bounds = parseSvgPathData('M0 0c0-10 10-10 10 0s10 10 10 0q5-5 10 0t10 0').getBounds();
      expect(bounds.left, 0);
      expect(bounds.right, closeTo(40, .01));
    });

    test('malformed data keeps what was read', () {
      expect(parseSvgPathData('M0 0L10 10L oops').getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
    });

    test('every path of the geometry parses to a non-empty shape', () {
      var count = 0;
      for (final figure in bodyGeometry.values) {
        for (final view in [figure.front, figure.back]) {
          for (final paths in view.parts.values) {
            for (final d in paths) {
              expect(parseSvgPathData(d).getBounds().isEmpty, isFalse);
              count++;
            }
          }
        }
      }
      expect(count, 333);
    });
  });

  Future<void> pumpMap(WidgetTester tester, Widget map) async {
    tester.view
      ..physicalSize = const Size(600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 406, child: map),
          ),
        ),
      ),
    );
  }

  testWidgets('front and back side by side; worked muscles in the semantics label', (tester) async {
    await pumpMap(tester, const BodyMap(levels: {'chest': 4, 'triceps': 2}, figure: 'female'));
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(2));
    expect(find.bySemanticsLabel('Mapa muscular: Pecho, Tríceps'), findsOneWidget);
    expect(tester.getSize(find.byType(BodyMap)).height, lessThanOrEqualTo(340));
  });

  testWidgets('a tap on a muscle reports its slug', (tester) async {
    final tapped = <String>[];
    await pumpMap(tester, BodyMap(levels: const {}, onMuscle: tapped.add));

    // Map a point of the male front view's left pectoral (viewBox coordinates) to the widget.
    const viewWidth = (406 - 6) / 2;
    final height = tester.getSize(find.byType(BodyMap)).height;
    final vb = bodyGeometry['male']!.front.viewBox;
    final scale = math.min(viewWidth / vb[2], height / vb[3]);
    final dx = (viewWidth - vb[2] * scale) / 2 - vb[0] * scale;
    final dy = (height - vb[3] * scale) / 2 - vb[1] * scale;
    final origin = tester.getTopLeft(find.byType(BodyMap));
    await tester.tapAt(origin + Offset(dx + 320 * scale, dy + 380 * scale));
    expect(tapped, ['chest']);

    await tester.tapAt(origin + const Offset(2, 2));
    expect(tapped, ['chest'], reason: 'outside the body nothing is reported');
  });

  testWidgets('the legend runs from less to more', (tester) async {
    await pumpMap(tester, const BodyMapLegend());
    expect(tester.getTopLeft(find.text('Menos')).dx, lessThan(tester.getTopLeft(find.text('Más')).dx));
  });
}
