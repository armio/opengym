import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/library/library_screen.dart';
import 'package:opengym/ui/screens/plan/plan_screen.dart';
import 'package:opengym/ui/screens/plan/plan_widgets.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../widgets/test_app.dart';
import '../library/test_view.dart';

void main() {
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

  Routine routine(String id, String name, [List<String> exIds = const []]) => Routine(
    id: id,
    name: name,
    emoji: 'barbell',
    ex: [for (final e in exIds) RoutineExercise(id: e, sets: 3, reps: 10)],
  );

  testWidgets('the week runs Monday to Sunday; a day takes a routine or goes back to rest', (tester) async {
    useTallView(tester);
    final app = testAppState()
      ..updatePlan((p) {
        p.routines.addAll([
          routine('r1', 'Torso', ['0025']),
          routine('r2', 'Pierna', ['0043', '0085']),
        ]);
        p.week['0'] = 'r2';
      });
    await pumpWithApp(tester, app, const PlanScreen());

    final days = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    final tops = [for (final d in days) tester.getTopLeft(find.text(d)).dy];
    expect(tops, orderedEquals([...tops]..sort()), reason: 'Monday first');
    expect(find.text('Descanso'), findsNWidgets(6));

    await tester.tap(find.text('Lunes'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Día de descanso')), findsOneWidget);
    expect(inSheet(find.text('2 ejercicios')), findsOneWidget);
    await tester.tap(inSheet(find.text('Torso')));
    await tester.pumpAndSettle();
    expect(app.plan.week, {'0': 'r2', '1': 'r1'});
    expect(find.byType(BottomSheet), findsNothing, reason: 'picking closes the sheet');
    expect(find.text('Descanso'), findsNWidgets(5));

    await tester.tap(find.text('Domingo'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Día de descanso')));
    await tester.pumpAndSettle();
    expect(app.plan.week, {'1': 'r1'});
    await settleAndDispose(tester, app);
  });

  testWidgets('the starter plan loads once from the empty state and is not duplicated from the tools', (tester) async {
    useTallView(tester);
    final app = testAppState();
    await pumpWithApp(tester, app, const PlanScreen());
    expect(find.textContaining('Aún no hay rutinas.'), findsOneWidget);

    await tester.tap(find.text('Cargar plan inicial'));
    await tester.pump();
    expect(find.text('Plan inicial cargado — Lun Empuje · Mié Tirón · Vie Pierna'), findsOneWidget);
    expect([for (final r in app.plan.routines) r.name], ['Empuje', 'Tirón', 'Pierna']);
    expect(app.plan.week, {'1': app.plan.routines[0].id, '3': app.plan.routines[1].id, '5': app.plan.routines[2].id});
    expect(app.plan.routines.first.ex, hasLength(6));

    // Reassign Monday, then load it again from the tools sheet: same three routines, week reset.
    app.updatePlan((p) => p.week['1'] = p.routines[2].id);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byTooltip('Herramientas del plan'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Cargar plan inicial')));
    await tester.pumpAndSettle();
    expect(app.plan.routines, hasLength(3));
    expect(app.plan.week['1'], app.plan.routines[0].id);
    await settleAndDispose(tester, app);
  });

  testWidgets('"Nueva" creates a routine and opens its editor; back lists it', (tester) async {
    useTallView(tester);
    final app = testAppState();
    await pumpWithApp(tester, app, const PlanScreen());

    await tester.tap(find.text('Nueva'));
    await tester.pumpAndSettle();
    final created = app.plan.routines.single;
    expect(created.name, 'Nueva rutina');
    expect(created.emoji, 'figureStrength');
    expect(find.byType(RoutineEditorScreen), findsOneWidget);
    expect(find.text('Aún no hay ejercicios — añade el primero.'), findsOneWidget);

    await tester.tap(find.byTooltip('Plan'));
    await tester.pumpAndSettle();
    expect(find.byType(RoutineEditorScreen), findsNothing);
    expect(find.text('Nueva rutina'), findsOneWidget);
    expect(find.text('0 ejercicios'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('routine rows summarise their exercises and open the editor', (tester) async {
    useTallView(tester);
    final app = testAppState()..updatePlan((p) => p.routines.add(routine('r1', 'Torso', ['0025', 'missing'])));
    await pumpWithApp(tester, app, const PlanScreen());

    expect(find.text('2 ejercicios · Barbell Bench Press, Ejercicio Desconocido'), findsOneWidget);
    await tester.tap(find.text('Torso'));
    await tester.pumpAndSettle();
    expect(tester.widget<RoutineEditorScreen>(find.byType(RoutineEditorScreen)).routineId, 'r1');
    await settleAndDispose(tester, app);
  });

  testWidgets('the exercise library opens from the Plan tab', (tester) async {
    useTallView(tester);
    final app = testAppState();
    await pumpWithApp(tester, app, const PlanScreen());

    await tester.tap(find.text('Biblioteca de ejercicios'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsNothing);
    await settleAndDispose(tester, app);
  });

  testWidgets('a long routine name is cut in the week, not the day name', (tester) async {
    useTallView(tester, width: 320);
    final app = testAppState()
      ..updatePlan((p) {
        p.routines.add(routine('r1', 'Full body con un nombre larguísimo que no cabe en la fila'));
        p.week['3'] = 'r1';
      });
    await pumpWithApp(tester, app, const PlanScreen());
    expect(tester.takeException(), isNull);
    final tag = tester.getSize(find.byType(RoutineTag));
    expect(tag.width, lessThan(320 * .6));
    await settleAndDispose(tester, app);
  });

  test('the Plan tab exports what other screens open', () {
    // Compile-time check of the public API (calendar for Home/Stats, config sheet for the workout).
    expect(showCalendarSheet, isNotNull);
    expect(showDayOverrideSheet, isNotNull);
    expect(showExerciseConfigSheet, isNotNull);
    expect(BodyMap.new, isNotNull);
  });
}
