/// The check-off algorithm of specs/ui.md §5.6 with the worked examples of §5.14, and the set
/// and unit edits of §5.4–§5.5.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/library.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';
import 'package:opengym/ui/screens/workout/set_editing.dart';

import '../../data/fake_server.dart';
import 'workout_harness.dart' show Ex;

final ExerciseIndex catalog = CatalogExerciseIndex(ExerciseCatalog(loadTestLibrary(), const []));

ActiveEntry reps(String id, int sets, {String? sg, num w = 60, num r = 8}) => ActiveEntry(
  id: id,
  sg: sg,
  target: {'id': id, 'mode': 'reps', 'sets': sets, 'reps': r, 'weight': w},
  sets: [for (var i = 0; i < sets; i++) SetRecord(w: w, r: r)],
);

ActiveEntry hold(String id, int sets) => ActiveEntry(
  id: id,
  target: {'id': id, 'mode': 'time', 'sets': sets, 'sec': 45, 'weight': 0},
  sets: [for (var i = 0; i < sets; i++) SetRecord(sec: 45, w: 0)],
);

ActiveEntry cardio(String id) => ActiveEntry(
  id: id,
  target: {'id': id, 'mode': 'cardio', 'sets': 1, 'min': 20, 'speed': 8},
  sets: [SetRecord(min: 20, speed: 8)],
);

ActiveWorkout session(List<ActiveEntry> entries) =>
    ActiveWorkout(id: 'a1', d: '2026-09-30', start: 0, name: 'Empuje', entries: entries);

/// (rest, askTop, workoutDone, exerciseDone) of a toggle.
(RestChange, bool, bool, bool) check(ActiveWorkout a, int entry, int set) {
  final t = toggleSet(a, entry, set, catalog);
  expect(t.checked, isTrue, reason: 'set $entry/$set should become done');
  return (t.rest, t.askTopWeight, t.workoutDone, t.exerciseDone);
}

void main() {
  group('toggleSet (§5.6)', () {
    test('A. a single lift: rest after each set, stopped by the last, then the top weight', () {
      final a = session([reps(Ex.bench, 3)]);
      expect(check(a, 0, 0), (RestChange.start, false, false, false));
      expect(check(a, 0, 1), (RestChange.start, false, false, false), reason: 'rechecking restarts the rest');
      expect(check(a, 0, 2), (RestChange.stop, true, true, true));
      expect(a.entries[0].asked, isTrue);
    });

    test('B. superset A+B then C: rest only after the last member; top weight per member', () {
      final a = session([reps(Ex.bench, 2, sg: 'x'), reps(Ex.row, 2, sg: 'x'), reps(Ex.squat, 1)]);
      expect(check(a, 0, 0), (RestChange.none, false, false, false), reason: 'A is not last in its unit');
      expect(check(a, 1, 0), (RestChange.start, false, false, false));
      expect(check(a, 0, 1), (RestChange.none, true, false, true), reason: 'A done, partner still open');
      expect(check(a, 1, 1), (RestChange.stop, true, false, true), reason: 'unit done, C still to come');
      expect(check(a, 2, 0), (RestChange.stop, true, true, true));
    });

    test('C. a timed hold: rest between sets, no top weight, the last set completes the workout', () {
      final a = session([hold(Ex.plank, 3)]);
      expect(check(a, 0, 0), (RestChange.start, false, false, false));
      expect(check(a, 0, 1), (RestChange.start, false, false, false));
      final t = toggleSet(a, 0, 2, catalog);
      expect(
        (t.rest, t.askTopWeight, t.workoutDone, t.exerciseDone, t.mode),
        (RestChange.stop, false, true, true, ExerciseMode.time),
      );
    });

    test('D. cardio: one interval logs the exercise; not the last unit → no completion', () {
      final a = session([cardio(Ex.run), reps(Ex.bench, 1)]);
      final t = toggleSet(a, 0, 0, catalog);
      expect(
        (t.rest, t.askTopWeight, t.workoutDone, t.exerciseDone, t.mode),
        (RestChange.stop, false, false, true, ExerciseMode.cardio),
      );
    });

    test('unchecking does nothing else, and the top weight is asked once per entry', () {
      final a = session([reps(Ex.bench, 2), reps(Ex.squat, 1)]);
      check(a, 0, 0);
      expect(check(a, 0, 1).$2, isTrue);
      final undo = toggleSet(a, 0, 1, catalog);
      expect((undo.checked, undo.rest, undo.askTopWeight), (false, RestChange.none, false));
      expect(a.entries[0].sets[1].done, isFalse);
      expect(check(a, 0, 1), (RestChange.stop, false, false, true), reason: '`asked` is kept on the entry');
    });

    test('the "whole workout" prompt needs the last unit completed, earlier ones are not checked', () {
      final skipped = session([reps(Ex.bench, 1), reps(Ex.squat, 1)]);
      expect(check(skipped, 1, 0).$3, isTrue, reason: 'exercise 1 skipped: still the whole workout');

      final backwards = session([reps(Ex.bench, 1), reps(Ex.squat, 1)]);
      check(backwards, 1, 0);
      expect(check(backwards, 0, 0).$3, isFalse, reason: 'completing an earlier unit last never shows it');
    });
  });

  group('sets and units', () {
    test('Añadir serie copies the last set unchecked and without effort; Quitar keeps one', () {
      final e = reps(Ex.bench, 1)
        ..sets.first.rir = 2
        ..sets.first.done = true;
      addSet(e, catalog);
      expect(e.sets.last.toJson(), {'w': 60, 'r': 8, 'done': false});
      final h = hold(Ex.plank, 1)..sets.first.sec = 38;
      addSet(h, catalog);
      expect(h.sets.last.toJson(), {'w': 0, 'sec': 38, 'done': false});
      final c = cardio(Ex.run);
      addSet(c, catalog);
      expect(c.sets.last.toJson(), {'min': 20, 'speed': 8, 'done': false});

      final one = reps(Ex.bench, 2);
      removeSet(one);
      removeSet(one);
      expect(one.sets, hasLength(1));
    });

    test('a null field is removed, not stored', () {
      final s = SetRecord(w: 60, r: 8, rpe: 8);
      setSetField(s, SetField.rpe, null);
      setSetField(s, SetField.w, 62.5);
      expect(s.toJson(), {'w': 62.5, 'r': 8, 'done': false});
      expect(setFieldOf(s, SetField.w), 62.5);
    });

    test('Anterior / Siguiente move by superset unit to its first entry', () {
      final a = session([reps(Ex.bench, 1), reps(Ex.incline, 1, sg: 'x'), reps(Ex.row, 1, sg: 'x'), reps(Ex.squat, 1)]);
      expect(unitsOf(a), [
        [0],
        [1, 2],
        [3],
      ]);
      expect(moveUnit(a, -1), isFalse);
      expect(moveUnit(a, 1), isTrue);
      expect(a.cur, 1);
      a.cur = 2;
      expect(moveUnit(a, 1), isTrue);
      expect(a.cur, 3);
      expect(moveUnit(a, 1), isFalse);
      expect(moveUnit(a, -1), isTrue);
      expect(a.cur, 1);
    });
  });
}
