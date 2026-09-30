/// Building a session, finishing it, and the top-weight sheet (specs/engine.md §2.14, §8.1–§8.2,
/// specs/ui.md §5.3, §5.9, §5.11), with engine-Q4 and engine-Q5.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1790755200000); // 2026-09-30 10:00 Madrid

Workout workout(String id, String d, List<JsonMap> entries) =>
    workoutFrom({'id': id, 'd': d, 'start': madrid.noonOf(d), 'end': madrid.noonOf(d) + 3600000, 'entries': entries});

JsonMap reps(String id, List<List<num>> sets, {num? topW, JsonMap? target}) => {
  'id': id,
  'sets': [
    for (final s in sets) {'w': s[0], 'r': s[1], 'done': s.length < 3 || s[2] == 1},
  ],
  'topW': ?topW,
  'target': ?target,
};

void main() {
  final index = indexWith();
  final push = Routine(
    id: 'r1',
    name: 'Empuje',
    prog: 'linear',
    ex: [
      RoutineExercise(id: '0025', sets: 3, reps: 5, weight: 60, sg: 'a'),
      RoutineExercise(id: '0047', sets: 2, reps: 10, weight: 40, sg: 'a'),
      RoutineExercise(id: '3220', sets: 1, min: 20, speed: 8),
    ],
  );

  group('startSession', () {
    test('builds each entry with its prescription and a target carrying id and mode (engine-Q4)', () {
      final state = TrainingState(
        catalog: index,
        workouts: [
          workout('w1', '2026-09-28', [
            reps(
              '0025',
              [
                [60, 5],
                [60, 5],
                [60, 5],
              ],
              target: {'id': '0025', 'mode': 'reps', 'sets': 3, 'reps': 5},
            ),
          ]),
        ],
      );
      final active = startSession(state, push, bw: 80.5, now: now, calendar: madrid);
      expect(active.d, '2026-09-30');
      expect(active.start, now.millisecondsSinceEpoch);
      expect(active.routineId, 'r1');
      expect(active.name, 'Empuje');
      expect(active.bw, 80.5);
      expect(active.entries.map((e) => e.id), ['0025', '0047', '3220']);

      final bench = active.entries[0];
      expect(bench.sg, 'a');
      expect(bench.plan.kind, 'up');
      expect(bench.plan.weight, 62.5);
      expect([for (final s in bench.sets) s.toJson()], List.filled(3, {'w': 62.5, 'r': 5, 'done': false}));
      expect(bench.target, {'id': '0025', 'sets': 3, 'reps': 5, 'weight': 60, 'sg': 'a', 'mode': 'reps'});

      expect(active.entries[1].plan.kind, 'first');
      final run = active.entries[2];
      expect(run.target['mode'], 'cardio');
      expect(run.plan.kind, 'off');
      expect(
        [for (final s in run.sets) s.toJson()],
        [
          {'min': 20, 'speed': 8, 'done': false},
        ],
      );
    });

    test('a freestyle session has no routine and a zero weigh-in is none', () {
      final active = startSession(
        TrainingState(catalog: index, workouts: const []),
        null,
        bw: 0,
        now: now,
        calendar: madrid,
      );
      expect(active.name, freestyleName);
      expect(active.routineId, isNull);
      expect(active.bw, isNull);
      expect(active.entries, isEmpty);
    });
  });

  group('finishWorkout', () {
    final history = [
      workout('w1', '2026-09-21', [
        reps('0025', [
          [80, 5],
          [85, 3],
        ], topW: 85),
        reps('0047', [
          [50, 8],
        ]),
      ]),
    ];
    final before = TrainingState(
      catalog: index,
      workouts: history,
      exWeights: {
        '0025': ExWeight(w: 85, d: '2026-09-21'),
        '0047': ExWeight(w: 50, d: '2026-09-21'),
      },
    );

    ActiveWorkout active(List<ActiveEntry> entries) => ActiveWorkout(
      id: 'a1',
      d: '2026-09-30',
      start: now.millisecondsSinceEpoch - 3600000,
      routineId: 'r1',
      name: 'Empuje',
      bw: 80,
      entries: entries,
    );

    ActiveEntry entry(String id, List<JsonMap> sets, {String? mode, num? topW}) => ActiveEntry(
      id: id,
      target: {'id': id, 'sets': sets.length, 'mode': ?mode},
      sets: [for (final s in sets) SetRecord.fromJson(s)],
      topW: topW,
    );

    test('stores the record, drops untouched entries and keeps unchecked sets', () {
      final done = finishWorkout(
        before,
        active([
          entry('0025', [
            {'w': 87.5, 'r': 3, 'done': true},
            {'w': 87.5, 'r': 2, 'done': false},
          ]),
          entry('0426', [
            {'w': 20, 'r': 10, 'done': false},
          ]),
          entry('3220', [
            {'min': 20, 'speed': 9, 'done': true},
          ]),
        ]),
        now: now,
      );
      final w = done.workout;
      expect(w.id, 'a1');
      expect(w.end, now.millisecondsSinceEpoch);
      expect(w.bw, 80);
      expect(w.entries.map((e) => e.id), ['0025', '3220']);
      expect(w.entries[0].sets, hasLength(2));
      expect(w.entries[0].topW, isNull);
      expect(w.entries[1].target, {'id': '3220', 'sets': 1, 'mode': 'cardio'});
      expect(w.vol, 262.5);
      expect(w.prs, ['0025']);
      expect(done.loadRecords, ['0025']);
      expect(done.exWeights.keys, ['0025']);
      expect(done.exWeights['0025']!.toJson(), {'w': 87.5, 'd': '2026-09-30'});
    });

    test('an e1RM record is reported only without a load record', () {
      final done = finishWorkout(
        before,
        active([
          entry('0047', [
            {'w': 50, 'r': 12, 'done': true},
          ]),
        ]),
        now: now,
      );
      expect(done.workout.prs, isEmpty);
      expect(done.e1rmRecords.single.exerciseId, '0047');
      expect(done.e1rmRecords.single.record.est, 70);
      expect(done.e1rmRecords.single.record.prev, 63.3);
    });

    test('timed and cardio entries never set a load record or a working weight (engine-Q5)', () {
      final done = finishWorkout(
        before,
        active([
          entry(
            '0025',
            [
              {'sec': 30, 'w': 120, 'done': true},
            ],
            mode: 'time',
            topW: 130,
          ),
        ]),
        now: now,
      );
      expect(done.workout.prs, isEmpty);
      expect(done.exWeights, isEmpty);
      expect(done.workout.entries.single.target!['mode'], 'time');
    });

    test('a confirmed topW raises the working weight; an exercise logged twice counts once', () {
      final done = finishWorkout(
        before,
        active([
          entry('0025', [
            {'w': 90, 'r': 1, 'done': true},
          ]),
          entry('0025', [
            {'w': 80, 'r': 5, 'done': true},
          ], topW: 92.5),
        ]),
        now: now,
      );
      expect(done.workout.prs, ['0025']);
      expect(done.exWeights['0025']!.w, 92.5);
      expect(done.workout.entries[1].topW, 92.5);
    });

    test('nothing done: an empty record with no records', () {
      final done = finishWorkout(
        before,
        active([
          entry('0025', [
            {'w': 90, 'r': 1, 'done': false},
          ]),
        ]),
        now: now,
      );
      expect(done.workout.entries, isEmpty);
      expect(done.workout.vol, 0);
      expect(done.exWeights, isEmpty);
    });
  });

  group('top-weight sheet', () {
    final state = TrainingState(
      catalog: index,
      workouts: [
        workout('w1', '2026-09-21', [
          reps('0025', [
            [80, 5],
          ], topW: 82.5),
        ]),
      ],
      exWeights: {'0025': ExWeight(w: 85, d: '2026-09-21')},
    );

    test('previous best: the higher of the load record and the working weight; 0 outside reps', () {
      expect(previousBest(state, ActiveEntry(id: '0025', target: {'mode': 'reps'})), 85);
      expect(previousBest(state, ActiveEntry(id: '0025', target: {'mode': 'time'})), 0);
      expect(previousBest(state, ActiveEntry(id: '3220')), 0);
    });

    test('suggestion: heaviest done set or previous best, else the planned weight', () {
      final bench = ActiveEntry(id: '0025', target: {'weight': 60}, sets: [SetRecord(w: 90, r: 3, done: true)]);
      expect(topWeightSuggestion(state, bench), 90);
      final fresh = TrainingState(catalog: index, workouts: const []);
      expect(topWeightSuggestion(fresh, ActiveEntry(id: '0047', target: {'weight': 40})), 40);
      expect(topWeightSuggestion(fresh, ActiveEntry(id: '0047')), 0);
    });

    test('confirming rounds to one decimal and never lowers the working weight', () {
      final raised = confirmTopWeight(
        92.54,
        current: ExWeight(w: 85, d: '2026-09-21'),
        today: '2026-09-30',
      )!;
      expect(raised.topW, 92.5);
      expect(raised.exWeight.toJson(), {'w': 92.5, 'd': '2026-09-30'});
      final lower = confirmTopWeight(
        70,
        current: ExWeight(w: 85, d: '2026-09-21'),
        today: '2026-09-30',
      )!;
      expect(lower.topW, 70);
      expect(lower.exWeight.toJson(), {'w': 85, 'd': '2026-09-30'});
      expect(confirmTopWeight(-1, today: '2026-09-30'), isNull);
      expect(confirmTopWeight(double.nan, today: '2026-09-30'), isNull);
    });
  });

  group('starter plan (data-B12)', () {
    test('creates the three routines and schedules Monday, Wednesday and Friday', () {
      final plan = PlanDoc();
      final created = loadStarterPlan(plan, now: now);
      expect(created.map((r) => r.name), ['Empuje', 'Tirón', 'Pierna']);
      expect(created.map((r) => r.emoji), ['barbell', 'pullup', 'legs']);
      expect(created.map((r) => r.id).toSet(), hasLength(3));
      expect(created[0].ex.first.toJson(), {'id': '0025', 'sets': 4, 'reps': 8, 'weight': 0});
      expect(created.map((r) => r.ex.length), [6, 5, 6]);
      expect(plan.week, {'1': created[0].id, '3': created[1].id, '5': created[2].id});
    });

    test('loading twice reuses the routines, and the English names count too', () {
      final plan = PlanDoc(
        routines: [Routine(id: 'old', name: 'push day')],
        week: {'2': 'old'},
      );
      final created = loadStarterPlan(plan, now: now);
      expect(created.map((r) => r.name), ['Tirón', 'Pierna']);
      expect(plan.week['1'], 'old');
      expect(plan.week['2'], 'old');
      expect(loadStarterPlan(plan, now: now), isEmpty);
      expect(plan.routines, hasLength(3));
    });
  });
}
