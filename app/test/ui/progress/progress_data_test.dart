import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';
import 'package:opengym/ui/screens/progress/progress_data.dart';

import '../../widgets/test_app.dart';
import 'progress_fixtures.dart';

int noonMs(String iso) {
  final d = DateTime.parse(iso);
  return DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch;
}

BodyWeight weighIn(String d, num w) => BodyWeight(d: d, w: w, t: noonMs(d));

void main() {
  final now = DateTime(2026, 9, 30, 18);

  group('body weight series', () {
    final entries = [
      weighIn('2026-05-01', 82),
      weighIn('2026-08-15', 79.4),
      weighIn('2026-09-01', 79),
      weighIn('2026-09-20', 78.5),
      weighIn('2026-09-30', 78.2),
    ];

    test('keeps the weigh-ins inside the range, oldest first, at their entry time', () {
      final points = bodyWeightPoints(entries, 30, now: now);
      expect([for (final p in points) p.d], ['2026-09-01', '2026-09-20', '2026-09-30']);
      expect([for (final p in points) p.y], [79, 78.5, 78.2]);
      expect(points.first.t, noonMs('2026-09-01'));
      expect(bodyWeightPoints(entries, 0, now: now), hasLength(5), reason: '"Todo" keeps everything');
      expect(weightChange(points), -0.8);
      expect(weightChange(points.take(1).toList()), isNull);
    });

    test('the frame stretches to the goal and pads 12 % on both sides', () {
      final points = bodyWeightPoints(entries, 90, now: now);
      final frame = ChartFrame.of(points, goal: 75);
      // Raw range 75 … 79.4 (the goal is below every weigh-in), padded by 12 % of 4.4.
      expect(frame.yMin, closeTo(75 - 0.528, 1e-9));
      expect(frame.yMax, closeTo(79.4 + 0.528, 1e-9));
      expect(frame.yFraction(75), greaterThan(0));
      expect(frame.yFraction(79.4), lessThan(1));
      // range/3 ≈ 1.65 → step 2: gridlines on even kilos inside the frame.
      expect(frame.step, 2);
      expect(frame.gridValues, [76, 78]);
      // Month ticks: the 1st of September falls inside the span.
      expect([for (final t in frame.ticks) t.label], ['Sep']);
      expect(frame.xFraction(points.first.t), 0);
      expect(frame.xFraction(points.last.t), 1);
    });

    test('a single point, or a flat line, still gets a range', () {
      final single = ChartFrame.of([ChartPoint(t: noonMs('2026-09-30'), y: 78)]);
      expect(single.yMin, closeTo(77 - .24, 1e-9));
      expect(single.yMax, closeTo(79 + .24, 1e-9));
      expect(single.ticks, isEmpty);
      expect(single.xFraction(noonMs('2026-09-30')), .5);
    });

    test('a short span gets start / middle / end ticks', () {
      final frame = ChartFrame.of([
        ChartPoint(t: noonMs('2026-09-10'), y: 78),
        ChartPoint(t: noonMs('2026-09-20'), y: 77),
      ]);
      expect([for (final t in frame.ticks) t.label], ['10 Sep', '15 Sep', '20 Sep']);
      expect([for (final t in frame.ticks) t.anchor], [TickAnchor.start, TickAnchor.middle, TickAnchor.end]);
    });

    test('the log runs newest first with the change since the previous weigh-in', () {
      final log = weighInLog(entries);
      expect([for (final w in log) w.entry.d], ['2026-09-30', '2026-09-20', '2026-09-01', '2026-08-15', '2026-05-01']);
      expect([for (final w in log) w.change], [-0.3, -0.5, -0.4, -2.6, null]);
    });

    test('nice steps', () {
      expect(ChartFrame.niceStep(0.3), 0.5);
      expect(ChartFrame.niceStep(1.65), 2);
      expect(ChartFrame.niceStep(2.2), 2.5);
      expect(ChartFrame.niceStep(7), 10);
      expect(ChartFrame.niceStep(12), 20);
    });
  });

  group('exercise progress', () {
    test('the e1RM series follows (d, start) whatever order the workouts were saved in', () {
      final app = testAppState();
      addTearDown(app.dispose);
      // Saved newest first, two sessions on the same day in reverse start order.
      app
        ..saveWorkout(progressWorkout('c', '2026-09-20', entries: [repsEntry('0025', 90, r: 5)]))
        ..saveWorkout(progressWorkout('b2', '2026-09-10', hour: 19, entries: [repsEntry('0025', 85, r: 5)]))
        ..saveWorkout(progressWorkout('b1', '2026-09-10', hour: 8, entries: [repsEntry('0025', 80, r: 5)]))
        ..saveWorkout(progressWorkout('a', '2026-09-01', entries: [repsEntry('0025', 100, r: 1)]));

      final progress = ExerciseProgress.of(app.trainingState, '0025');
      expect([for (final p in progress.e1rm) p.d], ['2026-09-01', '2026-09-10', '2026-09-10', '2026-09-20']);
      expect([for (final p in progress.e1rm) p.y], [100, 93.3, 99.2, 105]);
      expect(progress.e1rm[1].t, lessThan(progress.e1rm[2].t), reason: 'the morning session comes first');
      expect([for (final p in progress.e1rmPoints) p.t], orderedEquals([for (final p in progress.e1rm) p.t]));
      expect(progress.best1rm!.est, 105);
      expect((progress.best1rm!.w, progress.best1rm!.r, progress.best1rm!.d), (90, 5, '2026-09-20'));
      expect(progress.bestLoad, 100);
      expect(progress.bestTop, 100);
      expect(progress.metrics, [ExerciseMetric.top, ExerciseMetric.e1rm]);
      expect(progress.resolve(ExerciseMetric.effort), ExerciseMetric.top, reason: 'no rated sessions');
      expect([for (final p in progress.recent) p.d], ['2026-09-20', '2026-09-10', '2026-09-10', '2026-09-01']);
    });

    test('the latest mode decides the curve; effort needs three rated sessions', () {
      final app = testAppState();
      addTearDown(app.dispose);
      app
        ..saveWorkout(progressWorkout('a', '2026-09-01', entries: [timeEntry('2135', 40)]))
        ..saveWorkout(progressWorkout('b', '2026-09-08', entries: [timeEntry('2135', 50)]));
      final timed = ExerciseProgress.of(app.trainingState, '2135');
      expect(timed.mode, ExerciseMode.time);
      expect(timed.unitFor('kg'), 's');
      expect([for (final p in timed.topPoints('rir')) p.y], [40, 50]);
      expect(timed.hasE1rm, isFalse);

      for (final (i, rir) in [(1, 2), (2, 1), (3, 0)]) {
        app.saveWorkout(progressWorkout('r$i', '2026-09-0$i', entries: [repsEntry('0025', 60, rir: rir)]));
      }
      final rated = ExerciseProgress.of(app.trainingState, '0025');
      expect(rated.hasEffort, isTrue);
      expect(rated.metrics, contains(ExerciseMetric.effort));
      expect([for (final p in rated.effortPoints('rpe')) p.y], [8, 9, 10]);
      final top = rated.topPoints('rir');
      expect([for (final p in top) p.m], [.5, .75, 1]);
      expect(top.last.note, 'RIR 0');
    });
  });

  group('history', () {
    test('groups by month, newest first, same-day sessions by start', () {
      final workouts = [
        progressWorkout('aug', '2026-08-30'),
        progressWorkout('sep-am', '2026-09-02', hour: 8),
        progressWorkout('sep-pm', '2026-09-02', hour: 19),
        progressWorkout('jul', '2026-07-15'),
        progressWorkout('sep-late', '2026-09-28'),
      ];
      final months = workoutsByMonth(workouts);
      expect([for (final m in months) m.key], ['2026-09', '2026-08', '2026-07']);
      expect([for (final m in months) m.label], ['Septiembre 2026', 'Agosto 2026', 'Julio 2026']);
      expect([for (final w in months.first.workouts) w.id], ['sep-late', 'sep-pm', 'sep-am']);
      expect(workoutsByMonth(const []), isEmpty);
      expect(workoutCount(1), '1 entrenamiento');
      expect(workoutCount(3), '3 entrenamientos');
    });

    test('set labels never break inside a set', () {
      final app = testAppState();
      addTearDown(app.dispose);
      final entry = repsEntry('0025', 60, sets: 2, rir: 2);
      expect(doneSetsLine(app.exerciseIndex, entry), '60×8 (RIR 2)  ·  60×8 (RIR 2)');
      expect(doneSetsLine(app.exerciseIndex, WorkoutEntry(id: '0025')), 'sin series');
    });
  });

  group('summary', () {
    test('weekly counts cover the last weeks up to the current one', () {
      final workouts = [
        progressWorkout('a', '2026-09-28'),
        progressWorkout('b', '2026-09-30'),
        progressWorkout('c', '2026-09-23'),
        progressWorkout('old', '2026-06-01'),
      ];
      final weeks = weeklyCounts(workouts, now: now, weeks: 3);
      expect([for (final w in weeks) w.monday], ['2026-09-14', '2026-09-21', '2026-09-28']);
      expect([for (final w in weeks) w.count], [0, 1, 2]);
      expect(
        totalVolume([
          progressWorkout('v', '2026-09-01', entries: [repsEntry('0025', 50)]),
        ]),
        1200,
      );
      expect(totalDuration([progressWorkout('t', '2026-09-01', minutes: 45)]), 45 * 60000);
    });

    test('the seeded history covers every section', () {
      final app = seededProgressApp();
      addTearDown(app.dispose);
      expect(app.workouts.length, greaterThan(30));
      expect(hasEffort(app.workouts), isTrue);
      expect(app.bodyWeights, hasLength(40));
    });
  });
}
