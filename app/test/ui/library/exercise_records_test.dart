import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/library/exercise_records.dart';

/// Vectors from specs/engine.md §10.14–§10.16 and specs/ui.md §8.
void main() {
  Workout workout(String d, int start, String exId, List<Map<String, Object?>> sets, {Map<String, Object?>? target}) =>
      Workout.fromJson({
        'id': 'w$start',
        'd': d,
        'start': start,
        'end': start,
        'entries': [
          {'id': exId, 'sets': sets, 'topW': null, 'target': ?target},
        ],
      });
  Map<String, Object?> set(num w, num r, {bool done = true}) => {'w': w, 'r': r, 'done': done};
  bool isCardio(String id) => id == 'run';

  test('estimateOneRepMax follows Epley with the rep cap', () {
    expect(estimateOneRepMax(100, 1), 100);
    expect(estimateOneRepMax(62.5, 1), 62.5);
    expect(estimateOneRepMax(100, 5), 116.7);
    expect(estimateOneRepMax(100, 10), 133.3);
    expect(estimateOneRepMax(80, 8), 101.3);
    expect(estimateOneRepMax(60, 3), 66);
    expect(estimateOneRepMax(101.25, 7), 124.9);
    expect(estimateOneRepMax(100, 3), isA<int>());
    expect(estimateOneRepMax(100, 12), 140);
    expect(estimateOneRepMax(100, 12.4), isNull);
    expect(estimateOneRepMax(100, 2.5), 110);
    expect(estimateOneRepMax(100, 1.2), 103.3);
    for (final (w, r) in [(100, 13), (60, 30), (0, 5), (-100, 5), (100, 0), (100, -3), (null, 5), (100, null)]) {
      expect(estimateOneRepMax(w, r), isNull, reason: '($w, $r)');
    }
    expect(estimateOneRepMax(double.nan, 5), isNull);
    expect(estimateOneRepMax(double.infinity, 5), isNull);
  });

  test('bestOneRepMax keeps the earliest highest estimate of the first entry per workout', () {
    final workouts = [
      workout('2026-01-01', 1, 'bench', [set(80, 5)]),
      workout('2026-01-08', 2, 'squat', [set(100, 5)]),
      workout('2026-01-15', 3, 'bench', [set(90, 5), set(90, 3, done: false)]),
      workout('2026-01-22', 4, 'bench', [set(85, 5)]),
      workout('2026-01-29', 5, 'run', [
        {'min': 30, 'speed': 10, 'done': true},
      ]),
    ];
    final best = bestOneRepMax(workouts, 'bench')!;
    expect((best.est, best.w, best.r, best.d), (105, 90, 5, '2026-01-15'));
    expect(bestOneRepMax(workouts, 'run'), isNull);
    expect(bestOneRepMax(workouts, 'nope'), isNull);
    expect(bestOneRepMax(const [], 'bench'), isNull);
  });

  test('bestWeights counts done sets and topW of reps-mode entries only (engine-Q5)', () {
    final workouts = [
      workout('2026-01-01', 1, 'bench', [set(80, 5), set(120, 1, done: false)]),
      Workout.fromJson({
        'id': 'w2',
        'd': '2026-01-02',
        'start': 2,
        'end': 2,
        'entries': [
          {
            'id': 'bench',
            'topW': 90,
            'sets': [set(85, 5)],
          },
          {
            'id': 'plank',
            'topW': null,
            'target': {'mode': 'time'},
            'sets': [
              {'sec': 60, 'w': 20, 'done': true},
            ],
          },
          {
            'id': 'run',
            'topW': null,
            'sets': [
              {'min': 20, 'speed': 9, 'done': true},
            ],
          },
        ],
      }),
    ];
    final best = bestWeights(workouts, isCardio: isCardio);
    expect(best, {'bench': 90});
  });

  test('lastSessionFor returns the done sets of the latest session that has any', () {
    final workouts = [
      workout('2026-01-01', 1, 'bench', [set(80, 5)]),
      workout('2026-01-08', 2, 'bench', [set(85, 5), set(85, 4)], target: {'mode': 'reps'}),
      workout('2026-01-15', 3, 'bench', [set(90, 5, done: false)]),
    ];
    final last = lastSessionFor(workouts, 'bench')!;
    expect(last.d, '2026-01-08');
    expect(last.mode, 'reps');
    expect([for (final s in last.sets) s.r], [5, 4]);
    expect(lastSessionFor(workouts, 'squat'), isNull);
  });

  test('setLabel formats each mode like the original', () {
    SetRecord s(Map<String, Object?> json) => SetRecord.fromJson(json);
    expect(setLabel(s({'w': 60, 'r': 10}), 'reps'), '60×10');
    expect(setLabel(s({'min': 20, 'speed': 9}), 'cardio'), '20 min @ 9 km/h');
    expect(setLabel(s({'sec': 45, 'w': 0}), 'time'), '0:45');
    expect(setLabel(s({'sec': 90, 'w': 20}), 'time'), '1:30 · 20');
    expect(setLabel(s({'w': 0, 'r': 0}), 'reps'), '0×0');
    expect(setLabel(s({}), 'cardio'), '0 min @ 0 km/h');
    expect(setLabel(s({'w': 60, 'r': 10, 'rir': 1.5}), 'reps'), '60×10 (RIR 1,5)');
    expect(setLabel(s({'w': 60, 'r': 10, 'rpe': 8}), 'reps'), '60×10 (RPE 8)');
    expect(setLabel(s({'w': 60, 'r': 10, 'rir': 2, 'rpe': 8}), 'reps'), '60×10 (RIR 2)');
    expect(setLabel(s({'min': 20, 'speed': 9, 'rpe': 8}), 'cardio'), '20 min @ 9 km/h');
    expect(formatSeconds(605), '10:05');
    expect(formatSeconds(44.6), '0:45');
    expect(formatSeconds(-5), '0:00');
  });

  test('modeOf: an explicit mode wins, else the body part decides', () {
    expect(modeOf('time', cardio: false), 'time');
    expect(modeOf(null, cardio: true), 'cardio');
    expect(modeOf('bogus', cardio: false), 'reps');
  });
}
