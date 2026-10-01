/// Inicio (specs/ui.md §3.2, contract §6): the states of today's card, the Coach card, the week
/// strip, body weight, the streak, the header and pull-to-refresh.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/home/home_screen.dart';
import 'package:opengym/ui/screens/library/library_screen.dart';
import 'package:opengym/ui/screens/settings/settings_screen.dart';
import 'package:opengym/ui/screens/workout/workout_screen.dart';
import 'package:opengym/ui/shell.dart';
import 'package:provider/provider.dart';

import '../../data/fake_server.dart';
import '../workout/workout_harness.dart';

Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

Routine routine(String id, String name, List<RoutineExercise> ex) =>
    Routine(id: id, name: name, emoji: 'barbell', ex: ex);

/// Home under a [ShellController], as in the shell.
Future<ShellController> pumpHome(WidgetTester tester, WorkoutHarness h, {double width = 390}) async {
  final shell = ShellController();
  addTearDown(shell.dispose);
  await h.pump(
    tester,
    ChangeNotifierProvider.value(value: shell, child: const HomeScreen()),
    width: width,
  );
  return shell;
}

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no plan: the welcome card loads the starter plan, or sends to Claude or the plan', (tester) async {
    final h = WorkoutHarness();
    final shell = await pumpHome(tester, h);
    expect(find.text('¡Bienvenido!'), findsOneWidget);
    expect(find.text('Día de descanso'), findsNothing);

    await tapAndSettle(tester, find.text('Pídele un plan a Claude'));
    expect(shell.tab, AppTab.coach);
    await tapAndSettle(tester, find.text('Crear mi propio plan'));
    expect(shell.tab, AppTab.plan);

    await tapAndSettle(tester, find.text('Cargar plan inicial'));
    expect([for (final r in h.app.plan.routines) r.name], ['Empuje', 'Tirón', 'Pierna']);
    expect(find.text('¡Bienvenido!'), findsNothing);
    expect(find.text('Empezar Tirón'), findsOneWidget, reason: 'Wednesday is pull day');
    await h.dispose(tester);
  });

  testWidgets("today's routine: its reschedule, a preview of its exercises, and Empezar → check-in", (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(
      routine('r1', 'Empuje', [
        repsEx(Ex.bench, sets: 4, reps: 8, weight: 60),
        repsEx(Ex.incline),
        repsEx(Ex.row),
        repsEx(Ex.squat),
        RoutineExercise(id: Ex.run, sets: 1, min: 20, speed: 8),
      ]),
    );
    h.app.updateSchedule((s) => s.dayPlan['2026-09-30'] = 'r1');
    await pumpHome(tester, h);

    expect(find.text('HOY · REPROGRAMADO'), findsOneWidget);
    expect(find.text('5 ejercicios'), findsOneWidget);
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('4 × 8 · 60 kg'), findsOneWidget);
    expect(find.text('+1 ejercicio más'), findsOneWidget);

    await tapAndSettle(tester, find.text('Empezar Empuje'));
    expect(inSheet(find.text('Chequeo rápido')), findsOneWidget);
    await tapAndSettle(tester, inSheet(find.text('Guardar y empezar')));
    expect(h.active.routineId, 'r1');
    expect(find.byType(WorkoutScreen), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('rest day: tapping plans the day, "Entrenar igualmente" opens the chooser', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(routine('r1', 'Empuje', [repsEx(Ex.bench)]));
    await pumpHome(tester, h);

    expect(find.text('Día de descanso'), findsOneWidget);
    await tapAndSettle(tester, find.text('Día de descanso'));
    expect(inSheet(find.text('mié, 30 sept')), findsOneWidget);
    await tapAndSettle(tester, inSheet(find.text('Empuje')));
    expect(h.app.schedule.dayPlan['2026-09-30'], 'r1');
    expect(find.text('Empezar Empuje'), findsOneWidget);

    h.app.updateSchedule((s) => s.dayPlan['2026-09-30'] = 'rest');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.text('Entrenar igualmente'));
    expect(find.text('Empezar entrenamiento'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('a workout in progress: the banner resumes it', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(routine('r1', 'Empuje', [repsEx(Ex.bench, sets: 2)]), today: true);
    await h.start(h.app.plan.routineById('r1'));
    h.controller.toggle(0, 0);
    h.timers.stopRest();
    await pumpHome(tester, h);

    expect(find.text('Empuje — en curso'), findsOneWidget);
    expect(find.text(' · 1/2 series'), findsOneWidget);
    expect(find.text('Empezar Empuje'), findsNothing);
    await tapAndSettle(tester, find.text('Seguir'));
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(find.text('Ejercicio 1 / 1'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets("Claude's pending proposals: a card that opens the Coach tab", (tester) async {
    final server = FakeSyncServer()
      ..putProposal({'id': 'p1', 'kind': 'nochange', 'status': 'pending', 'reading': 'Bien', 'createdAt': 1})
      ..putProposal({'id': 'p2', 'kind': 'nochange', 'status': 'pending', 'reading': 'Bien', 'createdAt': 2});
    final h = WorkoutHarness(server: server);
    final shell = await pumpHome(tester, h);
    expect(find.textContaining('propuesta'), findsNothing);

    await h.app.sync();
    await tester.pumpAndSettle();
    expect(find.text('2 propuestas de Claude'), findsOneWidget);
    await tapAndSettle(tester, find.text('Revisar'));
    expect(shell.tab, AppTab.coach);
    await h.dispose(tester);
  });

  testWidgets('the week strip marks trained, rescheduled and planned days; a day opens its sheet', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(routine('r1', 'Empuje', [repsEx(Ex.bench)]));
    h.app.updatePlan((p) => p.week['5'] = 'r1'); // Fridays
    h.app.updateSchedule((s) => s.dayPlan['2026-10-03'] = 'r1');
    h.app.saveWorkout(
      pastWorkout('w1', '2026-09-28', [
        repsEntry(Ex.bench, [
          [60, 8],
        ]),
      ]),
    );
    await pumpHome(tester, h);

    expect(find.text('Esta semana'), findsOneWidget);
    for (final day in ['LU', 'MA', 'MI', 'JU', 'VI', 'SÁ', 'DO']) {
      expect(find.text(day), findsOneWidget);
    }
    await tapAndSettle(tester, find.byTooltip('Semana siguiente'));
    expect(find.text('5 oct – 11 oct'), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('Semana anterior'));

    await tapAndSettle(tester, find.text('3'));
    expect(inSheet(find.text('sáb, 3 oct')), findsOneWidget);
    expect(inSheet(find.text('Volver al plan semanal')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('body weight: latest, change coloured by the goal, the goal line; Registrar and Meta', (tester) async {
    final h = WorkoutHarness();
    h.app
      ..setBodyWeight(81.0, date: '2026-09-27', t: 1)
      ..setBodyWeight(80.4, date: '2026-09-29', t: 2)
      ..updateSettings((s) => s.targetW = 78);
    // Wider than a phone: the shared weight picker does not fit the test font at 390 px.
    await pumpHome(tester, h, width: 520);

    expect(find.text('80,4 kg', findRichText: true), findsOneWidget);
    expect(find.text('0,6'), findsOneWidget, reason: 'the change since the previous weigh-in');
    expect(find.text('Meta 78 kg · 2,4 kg por perder'), findsOneWidget);
    expect(find.text('mar, 29 sept'), findsOneWidget);

    await tapAndSettle(tester, find.text('Registrar'));
    expect(inSheet(find.text('Registrar peso corporal')), findsOneWidget);
    await tapAndSettle(tester, inSheet(find.text('Guardar')));
    expect(h.app.lastBodyWeight!.d, '2026-09-30');
    expect(find.text('mié, 30 sept'), findsOneWidget);

    await tapAndSettle(tester, find.text('78').first);
    expect(inSheet(find.text('Peso objetivo')), findsOneWidget);
    await tapAndSettle(tester, inSheet(find.text('Eliminar meta')));
    expect(h.app.settings.targetW, isNull);
    expect(find.text('Meta'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('streak and tiles: this week against the plan, the month, 30-day weight change', (tester) async {
    final h = WorkoutHarness();
    h.addRoutine(routine('r1', 'Empuje', [repsEx(Ex.bench)]), today: true);
    h.app
      ..saveWorkout(
        pastWorkout('w1', '2026-09-28', [
          repsEntry(Ex.bench, [
            [60, 8],
          ]),
        ]),
      )
      ..saveWorkout(
        pastWorkout('w2', '2026-09-22', [
          repsEntry(Ex.bench, [
            [60, 8],
          ]),
        ]),
      )
      ..setBodyWeight(82, date: '2026-09-10', t: DateTime(2026, 9, 10, 8).millisecondsSinceEpoch)
      ..setBodyWeight(80.8, date: '2026-09-29', t: DateTime(2026, 9, 29, 8).millisecondsSinceEpoch);
    await pumpHome(tester, h);

    expect(find.text('racha de 2 semanas'), findsOneWidget);
    expect(find.text('1 / 1 esta semana · 2 entrenamientos en total'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('−1,2 kg'), findsOneWidget);

    await tapAndSettle(tester, find.text('racha de 2 semanas'));
    expect(inSheet(find.text('Septiembre 2026')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('the header opens Ajustes and the library; pulling down syncs', (tester) async {
    final h = WorkoutHarness();
    await pumpHome(tester, h);
    expect(find.text('openGym'), findsOneWidget);
    expect(find.text('Miércoles, 30 de septiembre'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Ajustes'));
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('Atrás'));
    await tapAndSettle(tester, find.byTooltip('Biblioteca de ejercicios'));
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('Atrás'));

    final before = h.server.requests.length;
    // The view is 3000 px tall: the indicator arms after a quarter of it.
    await tester.fling(find.text('openGym'), const Offset(0, 900), 1000);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(h.server.requests.length, greaterThan(before));
    await h.dispose(tester);
  });
}
