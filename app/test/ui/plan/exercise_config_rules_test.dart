import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/library.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';
import 'package:opengym/ui/screens/plan/exercise_config_sheet.dart';

import '../../data/fake_server.dart';

/// The config sheet's save rules (specs/data-model.md §1.4.2, `ExConfig.save`).
void main() {
  final catalog = ExerciseCatalog(loadTestLibrary(), const []);
  final index = CatalogExerciseIndex(catalog);
  const lift = '0025'; // barbell bench press (chest)
  const cardio = '0798'; // stationary bike walk

  Map<String, dynamic> save(RoutineExercise c, String mode, {Routine? routine}) =>
      saveExerciseConfig(index, c, mode: mode, routine: routine).toJson();

  group('reps', () {
    test('blanks and zeros take the defaults; mode is always written', () {
      expect(save(RoutineExercise(id: lift, sets: 0), 'reps'), {
        'id': lift,
        'sets': 3,
        'mode': 'reps',
        'reps': 10,
        'weight': 0,
      });
    });

    test('rounds like Math.round and clamps', () {
      final c = RoutineExercise(id: lift, sets: 2, reps: 7.5, weight: -5);
      expect(save(c, 'reps'), {'id': lift, 'sets': 2, 'mode': 'reps', 'reps': 8, 'weight': 0});
      expect(save(RoutineExercise(id: lift, sets: 4, reps: .4, weight: 62.5), 'reps')['reps'], 10, reason: '0 || 10');
      expect(save(RoutineExercise(id: lift, sets: 4, reps: 6, weight: 62.5), 'reps')['weight'], 62.5);
    });

    test('prog and inc only when set; an emptied rule means "follow the routine"', () {
      expect(save(RoutineExercise(id: lift, reps: 5, prog: '', inc: 0), 'reps'), isNot(contains('prog')));
      expect(save(RoutineExercise(id: lift, reps: 5, prog: '', inc: 0), 'reps'), isNot(contains('inc')));
      final out = save(RoutineExercise(id: lift, reps: 5, prog: 'greyskull', inc: 1.25), 'reps');
      expect(out['prog'], 'greyskull');
      expect(out['inc'], 1.25);
    });

    test('repsMin only when the effective policy is double: own rule or the routine\'s', () {
      expect(save(RoutineExercise(id: lift, reps: 12, repsMin: 8), 'reps'), isNot(contains('repsMin')));
      expect(
        save(RoutineExercise(id: lift, reps: 12, prog: 'double'), 'reps')['repsMin'],
        10,
        reason: 'reps − 2',
      );
      expect(save(RoutineExercise(id: lift, reps: 12, prog: 'double', repsMin: 8), 'reps')['repsMin'], 8);
      expect(
        save(RoutineExercise(id: lift, reps: 8, prog: 'double', repsMin: 11), 'reps')['repsMin'],
        8,
        reason: '≤ reps',
      );
      expect(
        save(RoutineExercise(id: lift, reps: 2, prog: 'double'), 'reps')['repsMin'],
        1,
        reason: '≥ 1',
      );

      final doubleRoutine = Routine(id: 'r', name: 'R', prog: 'double');
      expect(save(RoutineExercise(id: lift, reps: 10), 'reps', routine: doubleRoutine)['repsMin'], 8);
      expect(
        save(
          RoutineExercise(id: lift, reps: 10, prog: 'linear'),
          'reps',
          routine: doubleRoutine,
        ),
        isNot(contains('repsMin')),
        reason: 'the exercise rule wins',
      );
    });
  });

  group('time', () {
    test('sec defaults to 45 and weight to 0; rule and step kept', () {
      expect(save(RoutineExercise(id: '0001', sets: 2, sec: 0), 'time'), {
        'id': '0001',
        'sets': 2,
        'mode': 'time',
        'sec': 45,
        'weight': 0,
      });
      expect(save(RoutineExercise(id: '0001', sets: 3, sec: 62.5, weight: 10, prog: 'time', inc: 10), 'time'), {
        'id': '0001',
        'sets': 3,
        'mode': 'time',
        'sec': 63,
        'weight': 10,
        'prog': 'time',
        'inc': 10,
      });
    });

    test('never writes reps or repsMin', () {
      final out = save(RoutineExercise(id: lift, sets: 3, reps: 10, repsMin: 8, sec: 30, prog: 'double'), 'time');
      expect(out.keys, unorderedEquals(['id', 'sets', 'mode', 'sec', 'weight', 'prog']));
    });
  });

  group('cardio', () {
    test('sets/min/speed only: no mode, no progression', () {
      expect(
        save(RoutineExercise(id: cardio, sets: 0, min: 0, speed: 0, mode: 'reps', prog: 'linear', inc: 5), 'cardio'),
        {'id': cardio, 'sets': 1, 'min': 20, 'speed': 8},
      );
      expect(save(RoutineExercise(id: cardio, sets: 3, min: 12.4, speed: 9.5), 'cardio'), {
        'id': cardio,
        'sets': 3,
        'min': 12,
        'speed': 9.5,
      });
    });
  });

  group('form mode (critic-G4: cardio by body part)', () {
    final liftEx = catalog.byId(lift)!;
    final cardioEx = catalog.byId(cardio)!;

    test('a cardio exercise always shows the cardio form', () {
      expect(configFormMode(index, cardioEx, RoutineExercise(id: cardio, mode: 'reps')), 'cardio');
      final draft = initialConfigDraft(index, cardioEx, RoutineExercise(id: cardio, sets: 2, mode: 'time', sec: 30));
      expect(draft.min, 20);
      expect(draft.speed, 8);
    });

    test('a non-cardio entry stored as cardio is edited — and saved — as reps', () {
      final stored = RoutineExercise(id: lift, sets: 2, mode: 'cardio', min: 10, speed: 6);
      expect(configFormMode(index, liftEx, stored), 'reps');
      final draft = initialConfigDraft(index, liftEx, stored);
      expect(save(draft, configFormMode(index, liftEx, draft)), {
        'id': lift,
        'sets': 2,
        'mode': 'reps',
        'reps': 10,
        'weight': 0,
      });
    });

    test('a new exercise starts from defaultConfig', () {
      expect(initialConfigDraft(index, liftEx, null).toJson(), {
        'id': lift,
        'sets': 3,
        'mode': 'reps',
        'reps': 10,
        'weight': 0,
      });
      expect(initialConfigDraft(index, cardioEx, null).toJson(), {'id': cardio, 'sets': 1, 'min': 20, 'speed': 8});
    });

    test('switching mode keeps the values it has and fills only the missing ones', () {
      final reps = RoutineExercise(id: lift, sets: 5, mode: 'reps', reps: 5, weight: 100);
      final timed = withConfigMode(index, reps, 'time');
      expect(timed.mode, 'time');
      expect([timed.sets, timed.sec, timed.weight, timed.reps], [5, 45, 100, 5]);
      expect(reps.mode, 'reps', reason: 'the input is not changed');

      final ruled = withConfigMode(
        index,
        reps
          ..prog = 'double'
          ..inc = 5,
        'time',
      );
      expect([ruled.prog, ruled.inc], [null, null], reason: 'a reps rule and a kg step do not carry over');
      final kept = withConfigMode(index, RoutineExercise(id: lift, mode: 'reps', prog: 'off', inc: 5), 'time');
      expect([kept.prog, kept.inc], ['off', null], reason: '"off" is a time rule too');
      final same = withConfigMode(index, RoutineExercise(id: lift, prog: 'double', inc: 5), 'reps');
      expect([same.prog, same.inc], ['double', 5], reason: 'no mode change, nothing dropped');

      final back = withConfigMode(index, timed..sec = 30, 'reps');
      expect([back.mode, back.reps, back.sec, back.weight], ['reps', 5, 30, 100]);
      expect(save(back, 'reps'), {'id': lift, 'sets': 5, 'mode': 'reps', 'reps': 5, 'weight': 100});
    });
  });
}
