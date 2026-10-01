/// The guided workout's logic: session prefill, the rest and hold timers with their alerts and
/// feedback, the top-weight confirmation, adding, discarding and finishing (specs/ui.md §5,
/// engine.md §8, critic-G1/G10, contract §6).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/clock.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';
import 'package:opengym/ui/screens/workout/workout_screen.dart';

import 'workout_harness.dart';

Routine routine(List<RoutineExercise> ex, {String id = 'r1', String name = 'Empuje', String? prog}) =>
    Routine(id: id, name: name, emoji: 'barbell', prog: prog, ex: ex);

RoutineExercise plank({int sets = 2}) => RoutineExercise(id: Ex.plank, sets: sets, sec: 45, weight: 0, mode: 'time');

/// Collects the controller's prompts.
List<WorkoutPrompt> record(WorkoutHarness h) {
  final prompts = <WorkoutPrompt>[];
  final sub = h.controller.prompts.listen(prompts.add);
  addTearDown(sub.cancel);
  return prompts;
}

void main() {
  testWidgets('start: each entry prefilled with its prescription, target with id and mode', (tester) async {
    final h = WorkoutHarness();
    h.app.saveWorkout(
      pastWorkout('w1', '2026-09-28', [
        repsEntry(
          Ex.bench,
          [
            [60, 5],
            [60, 5],
            [60, 5],
          ],
          target: {'id': Ex.bench, 'mode': 'reps', 'sets': 3, 'reps': 5, 'weight': 60},
        ),
      ]),
    );
    final push = routine([
      repsEx(Ex.bench, sets: 3, reps: 5, weight: 60),
      repsEx(Ex.squat, sets: 2, reps: 5, weight: 80),
    ], prog: 'linear');
    h.addRoutine(push);
    h.store.log.clear();

    await h.start(push, bodyWeight: 80.5);

    final a = h.active;
    expect((a.d, a.routineId, a.name, a.bw, a.cur), ('2026-09-30', 'r1', 'Empuje', 80.5, 0));
    final bench = a.entries[0];
    expect([for (final s in bench.sets) s.toJson()], List.filled(3, {'w': 62.5, 'r': 5, 'done': false}));
    expect(bench.plan.kind, 'up');
    expect(whyText(bench.plan.why), 'La última vez, todas las repeticiones: 2,5 kg más.');
    expect(bench.target, {'id': Ex.bench, 'sets': 3, 'mode': 'reps', 'reps': 5, 'weight': 60});
    expect(a.entries[1].plan.kind, 'first');
    expect([for (final s in a.entries[1].sets) s.toJson()], List.filled(2, {'w': 80, 'r': 5, 'done': false}));
    expect(h.store.log.take(2), ['writeState', 'writeActive'], reason: 'state.json before active.json');
    await h.dispose(tester);
  });

  testWidgets('rest: after a set, ±15 s moves the alert, skip and −15 past zero cancel it', (tester) async {
    final h = WorkoutHarness();
    final push = routine([repsEx(Ex.bench, sets: 3)]);
    h.addRoutine(push);
    h.app.updateSettings((s) => s.restSec = 120);
    await h.start(push);
    final t0 = h.clock.nowMs();

    h.controller.toggle(0, 0);
    expect(h.feedback.events, ['check']);
    expect((h.timers.rest!.left, h.timers.rest!.total), (120, 120));
    expect(h.alerts.pending!.millisecondsSinceEpoch, t0 + 120000);

    h.timers.addRest(15);
    expect((h.timers.rest!.left, h.timers.rest!.total), (135, 135));
    expect(h.alerts.pending!.millisecondsSinceEpoch, t0 + 135000);
    h.timers.addRest(-15);
    expect(h.alerts.pending!.millisecondsSinceEpoch, t0 + 120000);

    h.advance(100);
    expect(h.timers.rest!.left, 20);
    h.timers.addRest(-30);
    expect(h.timers.rest, isNull, reason: '−15 past zero is a skip');
    expect(h.alerts.log.last, 'cancel');

    h.controller.toggle(0, 1);
    expect(h.timers.rest!.left, 120);
    h.timers.stopRest();
    expect((h.timers.rest, h.alerts.pending), (null, null));
    await h.dispose(tester);
  });

  testWidgets('rest on the wall clock: survives the background, beeps the last 3 s, ends with a toast', (tester) async {
    final h = WorkoutHarness();
    final prompts = record(h);
    final push = routine([repsEx(Ex.bench, sets: 2)]);
    h.addRoutine(push);
    await h.start(push);
    h.controller.toggle(0, 0);

    // Backgrounded for a minute: nothing ticks, the clock moves on; resuming recomputes.
    h.clock.advance(const Duration(seconds: 60));
    h.timers.tick();
    expect(h.timers.rest!.left, 30);

    h.advance(27);
    expect(h.feedback.events.last, 'countdown');
    h.advance(3);
    await tester.pump();
    expect(h.timers.rest, isNull);
    expect(h.feedback.events.last, 'over');
    expect(h.alerts.log.last, 'cancel', reason: 'in the foreground the app itself says it');
    expect(prompts.whereType<WorkoutToast>().single.message, '¡Descanso terminado — siguiente serie!');
    await h.dispose(tester);
  });

  testWidgets('a rest that ends in the background leaves the notification to fire', (tester) async {
    final h = WorkoutHarness();
    final push = routine([repsEx(Ex.bench, sets: 2)]);
    h.addRoutine(push);
    await h.start(push);
    h.controller.toggle(0, 0);
    final endsAt = h.alerts.pending;
    h.foreground = false;
    h.advance(90);
    expect(h.timers.rest, isNull);
    expect(h.alerts.pending, endsAt);
    expect(h.feedback.events, isNot(contains('over')));
    await h.dispose(tester);
  });

  testWidgets('a hold logs the seconds held and checks the set off; Cancelar logs nothing', (tester) async {
    final h = WorkoutHarness();
    final prompts = record(h);
    final core = routine([plank(sets: 3)]);
    h.addRoutine(core);
    await h.start(core);

    // Example C: the full 45 s, then rest.
    h.controller.startHold(0, 0);
    expect((h.timers.hold!.left, h.timers.hold!.label), (45, 'Front Plank With Twist'));
    h.advance(45);
    expect(h.timers.hold, isNull);
    expect(h.active.entries[0].sets[0].toJson(), {'w': 0, 'sec': 45, 'done': true});
    expect(h.timers.rest!.left, 90);
    expect(h.feedback.events, ['over', 'check']);

    // A hold stops the rest; "Listo" with 7 s showing logs 38 s.
    h.controller.startHold(0, 1);
    expect(h.timers.rest, isNull);
    h.advance(38);
    expect(h.timers.hold!.left, 7);
    h.timers.endHoldEarly();
    expect(h.active.entries[0].sets[1].toJson(), {'w': 0, 'sec': 38, 'done': true});

    // Cancelar.
    h.controller.startHold(0, 2);
    h.advance(10);
    h.timers.cancelHold();
    h.advance(60);
    expect(h.active.entries[0].sets[2].toJson(), {'w': 0, 'sec': 45, 'done': false});

    // The last set: the hold is logged and the workout complete — no top weight for a hold.
    h.controller.toggle(0, 2);
    await tester.pump();
    expect(prompts.whereType<AskTopWeight>(), isEmpty);
    expect(prompts.last, isA<WorkoutCompleted>());
    await h.dispose(tester);
  });

  testWidgets('critic-G1: finishing, discarding or replacing the workout cancels a running hold', (tester) async {
    final h = WorkoutHarness();
    final core = routine([plank()]);
    h.addRoutine(core);

    await h.start(core);
    h.controller.startHold(0, 0);
    await h.controller.finish();
    expect(h.timers.hold, isNull);

    await h.start(core);
    h.controller.startHold(0, 0);
    await h.controller.discard();
    expect(h.timers.hold, isNull);

    await h.start(core);
    final first = h.active.id;
    h.controller.startHold(0, 0);
    // Another session replaces it behind the controller's back (e.g. a reset).
    await h.app.startActive(
      ActiveWorkout(id: 'other', d: '2026-09-30', start: 0, entries: [h.active.entries[0].copy()]),
    );
    expect(h.timers.hold, isNull);
    h.advance(60);
    expect(h.active.id, isNot(first));
    expect(h.active.entries[0].sets[0].done, isFalse, reason: 'nothing written into the new session');
    await h.dispose(tester);
  });

  testWidgets('top weight: stored on the entry, raises the working weight and never lowers it', (tester) async {
    final h = WorkoutHarness();
    final prompts = record(h);
    final push = routine([repsEx(Ex.bench, sets: 2, weight: 60), repsEx(Ex.squat, sets: 1, weight: 100)]);
    h.addRoutine(push);
    h.app.setExWeight(Ex.bench, 70, date: '2026-09-01');
    await h.start(push);

    h.controller.toggle(0, 0);
    h.controller.toggle(0, 1);
    await tester.pump();
    expect(prompts.whereType<AskTopWeight>().single.entry, 0);
    expect(h.active.entries[0].asked, isTrue);

    expect(h.controller.saveTopWeight(0, 65, advance: false), TopWeightOutcome.tracked);
    expect(h.active.entries[0].topW, 65);
    expect(h.app.exWeights[Ex.bench]!.toJson(), {'w': 70, 'd': '2026-09-30'});
    await tester.pump();
    expect((prompts.last as WorkoutToast).message, 'Registrado — la próxima vez empiezas en 70 kg');

    expect(h.controller.saveTopWeight(0, 72.46, advance: true), TopWeightOutcome.advanced);
    expect(h.app.exWeights[Ex.bench]!.w, 72.5);
    expect(h.active.cur, 1, reason: '"Guardar y siguiente ejercicio" moves on');
    expect(h.controller.saveTopWeight(0, double.nan, advance: false), TopWeightOutcome.invalid);

    h.controller.toggle(1, 0);
    expect(h.controller.saveTopWeight(1, 100, advance: true), TopWeightOutcome.completed);
    await h.dispose(tester);
  });

  testWidgets('a bodyweight top weight of 0 is kept on the entry and as a working weight', (tester) async {
    final h = WorkoutHarness();
    final push = routine([repsEx('0251', sets: 1)]); // chest dip
    h.addRoutine(push);
    await h.start(push);
    h.controller.toggle(0, 0);
    expect(h.controller.saveTopWeight(0, 0, advance: false), TopWeightOutcome.tracked);
    expect(h.active.entries[0].topW, 0);
    expect(h.app.exWeights['0251']?.w, 0); // as the original (data-model §1.8); buildSets ignores 0
    await h.dispose(tester);
  });

  testWidgets('finish: the stored workout, its records and working weights; active.json goes last', (tester) async {
    final h = WorkoutHarness();
    h.app.saveWorkout(
      pastWorkout('w1', '2026-09-20', [
        repsEntry(Ex.bench, [
          [60, 5],
        ]),
        repsEntry(Ex.squat, [
          [100, 3],
        ]),
      ]),
    );
    final push = routine([
      repsEx(Ex.bench, sets: 2, reps: 5, weight: 62.5),
      repsEx(Ex.squat, sets: 1, reps: 5, weight: 100),
      repsEx(Ex.row, sets: 1, reps: 10, weight: 50),
      plank(sets: 1),
    ]);
    h.addRoutine(push);
    await h.start(push, bodyWeight: 80);
    for (final (entry, w, r) in [(0, 62.5, 5), (1, 100, 5)]) {
      h.controller.setField(entry, 0, 'w', w);
      h.controller.setField(entry, 0, 'r', r);
    }
    h.controller.toggle(0, 0); // bench 62.5×5, second set left unchecked
    h.controller.toggle(1, 0); // squat 100×5: same load, more reps → e1RM record
    h.controller.toggle(3, 0); // plank 45 s
    h.clock.advance(const Duration(minutes: 50));
    h.controller.toggle(0, 0);
    h.controller.toggle(0, 0);
    final id = h.active.id;
    h.store.log.clear();

    final summary = (await h.controller.finish())!;

    final w = h.app.workoutById(id)!;
    expect(h.app.active, isNull);
    expect(h.store.log, ['writeState', 'deleteActive']);
    expect(h.feedback.events.last, 'finished');
    expect((w.d, w.routineId, w.name, w.bw, w.end - w.start), ('2026-09-30', 'r1', 'Empuje', 80, 50 * 60000));
    expect([for (final e in w.entries) e.id], [Ex.bench, Ex.squat, Ex.plank], reason: 'untouched row dropped');
    expect([for (final s in w.entries[0].sets) s.done], [true, false], reason: 'unchecked sets are kept');
    expect(w.entries[0].target, {'id': Ex.bench, 'sets': 2, 'mode': 'reps', 'reps': 5, 'weight': 62.5});
    expect(w.entries[2].target!['mode'], 'time');
    expect(w.prs, [Ex.bench]);
    expect([for (final r in summary.e1rmRecords) r.exerciseId], [Ex.squat]);
    expect(w.vol, 62.5 * 5 + 100 * 5);
    expect(h.app.exWeights[Ex.bench]!.toJson(), {'w': 62.5, 'd': '2026-09-30'});
    expect(h.app.exWeights.containsKey(Ex.plank), isFalse);
    expect(summary.muscleLevels['chest'], greaterThan(0));
    await h.dispose(tester);
  });

  testWidgets('adding an exercise mid-session: prescribed, never in a superset, and on screen', (tester) async {
    final h = WorkoutHarness();
    h.app.saveWorkout(
      pastWorkout('w1', '2026-09-28', [
        repsEntry(
          Ex.squat,
          [
            [100, 5],
            [100, 5],
          ],
          target: {'id': Ex.squat, 'mode': 'reps', 'sets': 2, 'reps': 5},
        ),
      ]),
    );
    await h.start(null);
    expect((h.active.name, h.active.routineId, h.active.entries.length), ('Libre', null, 0));

    h.controller.addExercise(repsEx(Ex.squat, sets: 2, reps: 5, weight: 90, sg: 'x', prog: 'linear'));
    h.controller.addExercise(RoutineExercise(id: Ex.run, sets: 1, min: 25, speed: 10));
    final squat = h.active.entries[0];
    expect(squat.sg, isNull);
    expect(squat.target['mode'], 'reps');
    expect(squat.target['id'], Ex.squat);
    expect(squat.plan.kind, 'up');
    expect([for (final s in squat.sets) s.w], [105, 105]);
    expect(h.active.entries[1].target['mode'], 'cardio');
    expect(h.active.cur, 1);
    await h.dispose(tester);
  });

  testWidgets('discard: nothing is stored, the rest and its alert stop', (tester) async {
    final h = WorkoutHarness();
    final push = routine([repsEx(Ex.bench)]);
    h.addRoutine(push);
    await h.start(push);
    h.controller.toggle(0, 0);
    await h.controller.discard();
    expect((h.app.active, h.app.workouts.length, h.timers.rest, h.alerts.pending), (null, 0, null, null));
    expect(h.store.active, isNull);
    await h.dispose(tester);
  });

  testWidgets('the screen stays on while a workout is active and "Pantalla siempre encendida" is on', (tester) async {
    final h = WorkoutHarness();
    expect(h.wakeLock.held, isFalse);
    await h.start(null);
    expect(h.wakeLock.held, isTrue);
    h.app.updateSettings((s) => s.keepAwake = false);
    expect(h.wakeLock.held, isFalse);
    h.app.updateSettings((s) => s.keepAwake = true);
    expect(h.wakeLock.held, isTrue);
    await h.controller.finish();
    expect(h.wakeLock.log, ['acquire', 'release', 'acquire', 'release']);
    await h.dispose(tester);
  });

  test('a hold of junk seconds runs at least one second', () {
    final timers = WorkoutTimers(
      clock: FakeClock(DateTime(2026, 9, 30)),
      alerts: const NoRestAlerts(),
      feedback: RecordingFeedback(),
      isForeground: () => true,
    );
    timers.startHold(
      double.nan,
      label: 'x',
      target: const HoldTarget(activeId: 'a', entry: 0, set: 0),
    );
    expect(timers.hold!.total, 1);
    timers.dispose();
  });
}
