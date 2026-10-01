import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/ui/screens/progress/progress_screen.dart';
import 'package:opengym/ui/theme.dart';

import '../../widgets/test_app.dart';
import '../library/test_view.dart';
import 'progress_fixtures.dart';

void main() {
  HeatmapCell cell(WidgetTester tester, String iso) => tester.widget<HeatmapCell>(find.byKey(ValueKey('heat-$iso')));

  testWidgets('days are shaded by the quartiles of minutes trained', (tester) async {
    useTallView(tester, width: 390);
    mockPathProvider(tester);
    final app = testAppState()
      ..saveWorkout(progressWorkout('a', '2026-09-07', minutes: 10))
      ..saveWorkout(progressWorkout('b', '2026-09-08', minutes: 20))
      ..saveWorkout(progressWorkout('c', '2026-09-09', minutes: 30))
      ..saveWorkout(progressWorkout('d', '2026-09-10', minutes: 40))
      // An import without a clock still marks its day.
      ..saveWorkout(progressWorkout('e', '2026-09-11', minutes: 0))
      // Two short sessions on one day add up.
      ..saveWorkout(progressWorkout('f1', '2026-09-14', minutes: 15, hour: 8))
      ..saveWorkout(progressWorkout('f2', '2026-09-14', minutes: 15, hour: 19));
    await pumpWithApp(tester, app, const ProgressScreen(initialSection: ProgressSection.activity));

    expect(find.byType(HeatmapCell), findsNWidgets(53 * 7));
    // Positive minutes sorted [10, 20, 30, 30, 40]: t1 = 20, t2 = 30, t3 = 30.
    expect(cell(tester, '2026-09-07').level, 1);
    expect(cell(tester, '2026-09-08').level, 2);
    expect(cell(tester, '2026-09-09').level, 4);
    expect(cell(tester, '2026-09-10').level, 4);
    expect(cell(tester, '2026-09-11').level, 1);
    expect(cell(tester, '2026-09-14').level, 4);
    expect(cell(tester, '2026-09-12').level, 0);
    expect(cell(tester, '2026-09-30').today, isTrue);
    expect(cell(tester, '2026-10-04').future, isTrue);
    expect(cell(tester, '2026-09-12').onTap, isNull, reason: 'empty days do nothing');

    // The ramp: level 0 is the empty cell, level 4 the accent.
    final p = AppTheme.build(brightness: Brightness.dark).extension<AppPalette>()!;
    BoxDecoration paint(String iso) =>
        tester
                .widget<Container>(
                  find.descendant(of: find.byKey(ValueKey('heat-$iso')), matching: find.byType(Container)),
                )
                .decoration!
            as BoxDecoration;
    expect(paint('2026-09-12').color, p.heatCell(0));
    expect(paint('2026-09-10').color, p.acc);

    expect(find.text('6 días entrenados · 2h 10m en total'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('a day with one workout opens it; a day with several opens the calendar there', (tester) async {
    useTallView(tester, width: 390);
    mockPathProvider(tester);
    final app = testAppState()
      ..saveWorkout(progressWorkout('one', '2026-09-07', name: 'Empuje', minutes: 50))
      ..saveWorkout(progressWorkout('am', '2026-09-14', name: 'Mañana', hour: 8))
      ..saveWorkout(progressWorkout('pm', '2026-09-14', name: 'Tarde', hour: 19));
    await pumpWithApp(tester, app, const ProgressScreen(initialSection: ProgressSection.activity));

    await tester.tap(find.byKey(const ValueKey('heat-2026-09-07')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Empuje')), findsOneWidget);
    expect(find.text('Eliminar entrenamiento'), findsOneWidget);
    Navigator.of(tester.element(find.text('Eliminar entrenamiento'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('heat-2026-09-14')));
    await tester.pumpAndSettle();
    expect(find.text('Septiembre 2026'), findsWidgets);
    expect(find.text('3 entrenamientos · 2h 40m · 0 kg'), findsOneWidget, reason: 'the calendar month summary');
    await settleAndDispose(tester, app);
  });
}
