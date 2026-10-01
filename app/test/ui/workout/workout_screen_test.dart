/// The workout screens end to end: the launcher's branches, the start chooser, checking sets
/// with the rest bar and the top-weight sheet, holds, editing sets, adding an exercise,
/// discarding, and finishing through the summary (specs/ui.md §3.5, §5, contract §6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/workout/workout_screen.dart';
import 'package:opengym/ui/workout_launcher.dart';
import 'package:provider/provider.dart';

import 'workout_harness.dart';

Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
Finder inDialog(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

Routine push({String id = 'r1', String name = 'Empuje', List<RoutineExercise>? ex}) => Routine(
  id: id,
  name: name,
  emoji: 'barbell',
  ex: ex ?? [repsEx(Ex.bench, sets: 2, reps: 5, weight: 60), repsEx(Ex.squat, sets: 1, reps: 5, weight: 100)],
);

/// A screen with a button that runs `launcher.launch`, standing in for the tab bar.
class LaunchHost extends StatelessWidget {
  const LaunchHost({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => context.read<WorkoutLauncher>().launch(context),
        child: const Text('Entrenar'),
      ),
    ),
  );
}

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('launcher (contract §6)', () {
    testWidgets("today's routine: check-in, the weigh-in saved, the session on screen", (tester) async {
      final h = WorkoutHarness();
      h.addRoutine(push(), today: true);
      await h.pump(tester, const LaunchHost());

      await tapAndSettle(tester, find.text('Entrenar'));
      expect(inSheet(find.text('Chequeo rápido')), findsOneWidget);
      await tapAndSettle(tester, inSheet(find.text('Guardar y empezar')));

      expect(h.app.bodyWeights.single.toJson(), containsPair('w', 70));
      expect((h.active.routineId, h.active.bw), ('r1', 70));
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(find.text('Ejercicio 1 / 2'), findsOneWidget);

      // With a workout active the button resumes it, without another check-in.
      await tapAndSettle(tester, find.byTooltip('Ocultar'));
      expect(find.byType(WorkoutScreen), findsNothing);
      await tapAndSettle(tester, find.text('Entrenar'));
      expect(find.text('Chequeo rápido'), findsNothing);
      expect(find.text('Ejercicio 1 / 2'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('"Empezar sin pesarse" starts without a weight; "Elegir otro" opens the chooser', (tester) async {
      final h = WorkoutHarness();
      h.addRoutine(push(), today: true);
      await h.pump(tester, const LaunchHost());

      await tapAndSettle(tester, find.text('Entrenar'));
      await tapAndSettle(tester, inSheet(find.text('Elegir otro entrenamiento')));
      expect(h.app.active, isNull);
      expect(find.text('Empezar entrenamiento'), findsOneWidget);

      await tapAndSettle(tester, find.text('Empezar Empuje'));
      await tapAndSettle(tester, inSheet(find.text('Empezar sin pesarse')));
      expect((h.active.routineId, h.active.bw), ('r1', null));
      expect(h.app.bodyWeights, isEmpty);
      expect(find.text('Ejercicio 1 / 2'), findsOneWidget, reason: 'the chooser turns into the workout');
      await h.dispose(tester);
    });

    testWidgets('no routine today, or an empty one: straight to the chooser', (tester) async {
      final h = WorkoutHarness();
      h.addRoutine(push(ex: []), today: true);
      await h.pump(tester, const LaunchHost());
      await tapAndSettle(tester, find.text('Entrenar'));
      expect(find.text('Chequeo rápido'), findsNothing);
      expect(find.text('Empezar entrenamiento'), findsOneWidget);
      expect(find.text('Miércoles — hoy toca Empuje'), findsOneWidget);
      await h.dispose(tester);
    });
  });

  testWidgets('the chooser: today with its reschedule, the others, freestyle; without routines, a plan', (
    tester,
  ) async {
    final h = WorkoutHarness();
    h.addRoutine(push());
    h.addRoutine(push(id: 'r2', name: 'Pierna', ex: [repsEx(Ex.squat)]));
    h.app.updateSchedule((s) => s.dayPlan['2026-09-30'] = 'r2');
    await h.pump(tester, const WorkoutScreen());

    expect(find.text('Plan de hoy · reprogramado'), findsOneWidget);
    expect(find.text('Empezar Pierna'), findsOneWidget);
    expect(find.text('Otras rutinas'), findsOneWidget);
    expect(find.text('Empuje'), findsOneWidget);
    expect(find.text('Entrenamiento libre (elige sobre la marcha)'), findsOneWidget);
    expect(find.text('Crea primero un plan'), findsNothing);

    await tapAndSettle(tester, find.text('Entrenamiento libre (elige sobre la marcha)'));
    await tapAndSettle(tester, inSheet(find.text('Empezar sin pesarse')));
    expect((h.active.name, h.active.routineId), ('Libre', null));
    expect(find.text('Entrenamiento libre — añade tu primer ejercicio.'), findsOneWidget);
    await h.dispose(tester);

    final empty = WorkoutHarness();
    await empty.pump(tester, const WorkoutScreen());
    expect(find.text('Miércoles — día de descanso, pero nadie te lo impide'), findsOneWidget);
    expect(find.text('Crea primero un plan'), findsOneWidget);
    await empty.dispose(tester);
  });

  testWidgets('checking sets: rest bar, top weight, "Guardar y siguiente", the whole workout, summary', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(push());
    await h.start(h.app.plan.routineById('r1'), bodyWeight: 80);
    await h.pump(tester, const WorkoutScreen());

    await tapAndSettle(tester, find.bySemanticsLabel('Serie 1 hecha'));
    expect(find.text('1:30'), findsOneWidget);
    expect(h.alerts.pending, isNotNull);
    await tapAndSettle(tester, find.text('Saltar'));
    expect(find.text('1:30'), findsNothing);
    expect(h.alerts.pending, isNull);

    await tapAndSettle(tester, find.bySemanticsLabel('Serie 2 hecha'));
    expect(inSheet(find.text('Barbell Bench Press hecho')), findsOneWidget);
    expect(inSheet(find.text('Mejor anterior: 60 kg — ¡nuevo récord!')), findsNothing, reason: 'no history');
    await tapAndSettle(tester, inSheet(find.text('+1')));
    await tapAndSettle(tester, inSheet(find.text('Guardar y siguiente ejercicio')));
    expect((h.active.entries[0].topW, h.app.exWeights[Ex.bench]!.w), (61, 61));
    expect(find.text('Ejercicio 2 / 2'), findsOneWidget);

    await tapAndSettle(tester, find.bySemanticsLabel('Serie 1 hecha'));
    await tapAndSettle(tester, inSheet(find.text('Guardar')));
    expect(inDialog(find.text('¡Ese era todo el entrenamiento!')), findsOneWidget);
    await tapAndSettle(tester, inDialog(find.text('Terminar entrenamiento')));

    final id = h.app.workouts.single.id;
    expect(h.app.active, isNull);
    expect(inSheet(find.text('¡Entrenamiento completado!')), findsOneWidget);
    expect(inSheet(find.text('Nuevo récord: Barbell Bench Press')), findsOneWidget);
    expect(inSheet(find.text('2')), findsOneWidget, reason: 'two load records');

    // Locked: the backdrop does not close it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('¡Entrenamiento completado!'), findsOneWidget);

    await tapAndSettle(tester, inSheet(find.text('Duro')));
    expect(h.app.workoutById(id)!.rating, 'hard');
    await tapAndSettle(tester, inSheet(find.text('Duro')));
    expect(h.app.workoutById(id)!.rating, isNull, reason: 'tapping the selected rating clears it');
    await tester.enterText(inSheet(find.byType(TextField)), '  Buen día, ${'x' * 400}');
    await tapAndSettle(tester, inSheet(find.text('¡Genial!')));
    final note = h.app.workoutById(id)!.note!;
    expect(note.startsWith('Buen día, xxx'), isTrue);
    expect(note.length, lessThanOrEqualTo(300));
    expect(h.app.workoutById(id)!.toJson().containsKey('rating'), isFalse);
    expect(find.text('¡Entrenamiento completado!'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('finishing early asks first; with nothing checked it says so', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(push());
    await h.start(h.app.plan.routineById('r1'));
    await h.pump(tester, const WorkoutScreen());

    await tapAndSettle(tester, find.byTooltip('Terminar'));
    expect(inDialog(find.text('Nada registrado aún')), findsOneWidget);
    await tapAndSettle(tester, inDialog(find.text('Cancelar')));
    expect(h.app.active, isNotNull);

    await tapAndSettle(tester, find.bySemanticsLabel('Serie 1 hecha'));
    h.timers.stopRest();
    await tapAndSettle(tester, find.text('Terminar antes · 0/2 ejercicios'));
    expect(inDialog(find.text('Quedan 2 series sin marcar. ¿Terminar ahora?')), findsOneWidget);
    await tapAndSettle(tester, inDialog(find.text('Terminar entrenamiento')));
    expect(h.app.active, isNull);
    expect(h.app.workouts.single.entries.single.id, Ex.bench);
    await tapAndSettle(tester, find.text('¡Genial!'));
    await h.dispose(tester);
  });

  testWidgets('discarding asks, then throws the session away', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(push());
    await h.start(h.app.plan.routineById('r1'));
    await h.pump(tester, const WorkoutScreen());
    await tapAndSettle(tester, find.byTooltip('Descartar'));
    expect(inDialog(find.text('¿Descartar entrenamiento?')), findsOneWidget);
    await tapAndSettle(tester, inDialog(find.text('Descartar')));
    expect((h.app.active, h.app.workouts.length), (null, 0));
    expect(find.text('Empezar entrenamiento'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('steppers, the effort column of the profile, adding and removing sets', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(push(ex: [repsEx(Ex.bench, sets: 2, reps: 5, weight: 60)]));
    h.app.updateSettings((s) => s.effort = 'rpe');
    await h.start(h.app.plan.routineById('r1'));
    await h.pump(tester, const WorkoutScreen());

    expect(find.text('RPE'), findsOneWidget);
    // Row 1: weight −/+, reps −/+, RPE −/+.
    await tapAndSettle(tester, find.bySemanticsLabel('Más').at(0));
    await tapAndSettle(tester, find.bySemanticsLabel('Menos').at(1));
    await tapAndSettle(tester, find.bySemanticsLabel('Más').at(2));
    await tapAndSettle(tester, find.bySemanticsLabel('Más').at(2));
    expect(h.active.entries[0].sets[0].toJson(), {'w': 62.5, 'r': 4, 'done': false, 'rpe': 6.5});
    await tapAndSettle(tester, find.bySemanticsLabel('Menos').at(2));
    await tapAndSettle(tester, find.bySemanticsLabel('Menos').at(2));
    expect(h.active.entries[0].sets[0].toJson().containsKey('rpe'), isFalse, reason: 'below the floor clears');

    await tapAndSettle(tester, find.text('Añadir serie'));
    expect(h.active.entries[0].sets.map((s) => s.w), [62.5, 60, 60]);
    await tapAndSettle(tester, find.text('Quitar serie'));
    await tapAndSettle(tester, find.text('Quitar serie'));
    expect(h.active.entries[0].sets, hasLength(1));
    await tapAndSettle(tester, find.text('Quitar serie'));
    expect(h.active.entries[0].sets, hasLength(1), reason: 'the only set stays');
    await h.dispose(tester);
  });

  testWidgets('a timed set: ▶ runs the hold bar, "Listo" logs what was held and checks it off', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(
      push(
        ex: [RoutineExercise(id: Ex.plank, sets: 2, sec: 45, weight: 0, mode: 'time')],
      ),
    );
    await h.start(h.app.plan.routineById('r1'));
    await h.pump(tester, const WorkoutScreen());

    expect(find.text('SEGUNDOS'), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('Iniciar serie').first);
    expect(find.text('0:45'), findsOneWidget);
    h.clock.advance(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:35'), findsOneWidget);
    await tapAndSettle(tester, find.text('Listo'));
    expect(h.active.entries[0].sets[0].toJson(), {'w': 0, 'sec': 10, 'done': true});
    expect(find.text('1:30'), findsOneWidget, reason: 'then the rest, as for any set');
    await h.dispose(tester);
  });

  testWidgets('adding an exercise mid-session: picker, config sheet, then on screen', (tester) async {
    final h = WorkoutHarness();
    await h.start(null);
    await h.pump(tester, const WorkoutScreen());

    await tapAndSettle(tester, find.text('Añadir ejercicio'));
    await tester.enterText(inSheet(find.byType(TextField)), 'barbell full squat');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, inSheet(find.text('Barbell Full Squat')).first);
    await tapAndSettle(tester, inSheet(find.text('Añadir al entrenamiento')));
    expect(h.active.entries.single.id, Ex.squat);
    expect(h.active.entries.single.target, containsPair('mode', 'reps'));

    // The picker stays open for more; closing it shows the new exercise.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Ejercicio 1 / 1'), findsOneWidget);
    expect(find.text('Barbell Full Squat'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('a superset is shown as one card, and rest waits for its last member', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(
      push(
        ex: [
          repsEx(Ex.incline, sets: 1, sg: 'a'),
          repsEx(Ex.row, sets: 1, sg: 'a'),
          repsEx(Ex.squat, sets: 1),
        ],
      ),
    );
    await h.start(h.app.plan.routineById('r1'));
    await h.pump(tester, const WorkoutScreen());

    expect(find.text('Superserie 1 / 2'), findsOneWidget);
    expect(find.text('Superserie · hazlos seguidos, descansa después de ambos'), findsOneWidget);
    expect(find.text('Barbell Incline Bench Press'), findsOneWidget);
    expect(find.text('Barbell Bent Over Row'), findsOneWidget);

    await tapAndSettle(tester, find.bySemanticsLabel('Serie 1 hecha').first);
    expect(inSheet(find.textContaining('Luego termina el otro ejercicio de la superserie.')), findsOneWidget);
    await tapAndSettle(tester, inSheet(find.text('Guardar peso')));
    expect(h.timers.rest, isNull, reason: 'no rest before the partner');
    await h.dispose(tester);
  });
}
