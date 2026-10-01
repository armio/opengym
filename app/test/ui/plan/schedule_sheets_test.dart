import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/plan/plan_screen.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../widgets/test_app.dart';
import '../library/test_view.dart';

/// A button that runs [open] with a context under the app.
class _Opener extends StatelessWidget {
  const _Opener(this.open);

  final Future<void> Function(BuildContext context) open;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: AppButton('Abrir', onPressed: () => open(context))),
  );
}

void main() {
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

  AppState seeded() => testAppState()
    ..updatePlan((p) {
      p.routines.addAll([
        Routine(
          id: 'r1',
          name: 'Torso',
          emoji: 'arm',
          ex: [RoutineExercise(id: '0025')],
        ),
        Routine(id: 'r2', name: 'Pierna', emoji: 'legs'),
      ]);
      p.week['2'] = 'r1'; // Tuesdays
    });

  Future<void> open(WidgetTester tester, AppState app, Future<void> Function(BuildContext) fn) async {
    await pumpWithApp(tester, app, _Opener(fn));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('reschedule a date: another routine, rest, then back to the weekly plan', (tester) async {
    useTallView(tester);
    final app = seeded();
    // Tuesday 22 September: the week plans Torso.
    await open(tester, app, (c) => showDayOverrideSheet(c, '2026-09-22'));
    expect(inSheet(find.text('mar, 22 sept')), findsOneWidget);
    expect(inSheet(find.textContaining('Plan semanal: Torso')), findsOneWidget);
    expect(inSheet(find.textContaining('cambiado para este día')), findsNothing);
    expect(inSheet(find.text('Volver al plan semanal')), findsNothing);

    await tester.tap(inSheet(find.text('Pierna')));
    await tester.pumpAndSettle();
    expect(app.schedule.dayPlan, {'2026-09-22': 'r2'});
    expect(find.text('Pierna planificado para 22 sept'), findsOneWidget);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(inSheet(find.textContaining('cambiado para este día')), findsOneWidget);
    await tester.tap(inSheet(find.text('Descansar / saltar este día')));
    await tester.pumpAndSettle();
    expect(app.schedule.dayPlan, {'2026-09-22': 'rest'});
    expect(find.text('22 sept marcado como descanso'), findsOneWidget);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Volver al plan semanal')));
    await tester.pumpAndSettle();
    expect(app.schedule.dayPlan, isEmpty);
    expect(app.plan.week, {'2': 'r1'}, reason: 'the week itself never changes');
    await settleAndDispose(tester, app);
  });

  testWidgets('picking the routine the week already has still stores an override', (tester) async {
    useTallView(tester);
    final app = seeded();
    await open(tester, app, (c) => showDayOverrideSheet(c, '2026-09-29'));
    await tester.tap(inSheet(find.text('Torso')));
    await tester.pumpAndSettle();
    expect(app.schedule.dayPlan, {'2026-09-29': 'r1'});
    await settleAndDispose(tester, app);
  });

  testWidgets('the calendar opens on the month of a date read as local (critic-G2) and marks days', (tester) async {
    useTallView(tester);
    final app = seeded()
      ..updateSchedule((s) {
        s.dayPlan['2026-09-08'] = 'rest';
        s.dayPlan['2026-09-10'] = 'r2';
      })
      ..saveWorkout(
        Workout(
          id: 'w1',
          d: '2026-09-15',
          start: DateTime(2026, 9, 15, 18).millisecondsSinceEpoch,
          end: DateTime(2026, 9, 15, 19, 5).millisecondsSinceEpoch,
          routineId: 'r1',
          name: 'Torso',
          vol: 4250,
        ),
      );
    await open(tester, app, (c) => showCalendarSheet(c, startIso: '2026-09-01'));

    expect(inSheet(find.text('Septiembre 2026')), findsOneWidget);
    expect(inSheet(find.text('1 entrenamiento · 1h 5m · 4250 kg')), findsOneWidget);
    for (final h in ['LU', 'MA', 'MI', 'JU', 'VI', 'SÁ', 'DO']) {
      expect(inSheet(find.text(h)), findsOneWidget);
    }
    // 1 September 2026 is a Tuesday: one blank before it in a Monday-first grid.
    expect(tester.getCenter(inSheet(find.text('1'))).dx, greaterThan(tester.getCenter(inSheet(find.text('7'))).dx));
    expect(tester.getCenter(inSheet(find.text('7'))).dx, lessThan(tester.getCenter(inSheet(find.text('8'))).dx));

    await tester.tap(find.byTooltip('Mes siguiente'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Octubre 2026')), findsOneWidget);
    expect(inSheet(find.text('Sin entrenamientos este mes')), findsOneWidget);
    await tester.tap(find.byTooltip('Mes anterior'));
    await tester.pumpAndSettle();

    // A day without workouts closes the calendar and opens the reschedule sheet.
    await tester.tap(inSheet(find.text('10')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('jue, 10 sept')), findsOneWidget);
    expect(inSheet(find.text('Septiembre 2026')), findsNothing);
    await settleAndDispose(tester, app);
  });

  testWidgets('a trained day opens the workout through the given opener', (tester) async {
    useTallView(tester);
    final app = seeded()
      ..saveWorkout(
        Workout(id: 'w1', d: '2026-09-15', start: DateTime(2026, 9, 15, 18).millisecondsSinceEpoch, end: 0, name: 'A'),
      );
    Workout? opened;
    await open(
      tester,
      app,
      (c) => showCalendarSheet(c, startIso: '2026-09-15', openWorkout: (_, w) async => opened = w),
    );
    await tester.tap(inSheet(find.text('15')));
    await tester.pumpAndSettle();
    expect(opened?.id, 'w1');
    await settleAndDispose(tester, app);
  });
}
