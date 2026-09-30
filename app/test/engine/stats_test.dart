/// Stats and Home computations (specs/engine.md §8.3–§8.4, specs/ui.md §3.2, §3.6, §7.2).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1790755200000); // Wed 2026-09-30 10:00 Madrid

Workout session(String d, {int minutes = 60, num vol = 1000, List<JsonMap> entries = const []}) {
  final start = madrid.noonOf(d);
  return workoutFrom({
    'id': 'w$d',
    'd': d,
    'start': start,
    'end': start + minutes * 60000,
    'vol': vol,
    'entries': entries,
  });
}

void main() {
  group('heatmap', () {
    test('per-date totals: workouts, volume and minutes', () {
      final days = heatmapDays([
        session('2026-09-28', minutes: 45, vol: 1000),
        session('2026-09-28', minutes: 30, vol: 500),
        workoutFrom({'id': 'imp', 'd': '2026-09-20', 'entries': <dynamic>[]}),
      ]);
      expect(days['2026-09-28']!.workouts, 2);
      expect(days['2026-09-28']!.volume, 1500);
      expect(days['2026-09-28']!.minutes, 75);
      expect(days['2026-09-20']!.minutes, 0);
      final scale = HeatmapScale.of(days);
      expect(scale.levelOf(days['2026-09-20']), 1); // a day without a clock
      expect(scale.levelOf(days['2026-09-28']), 4);
      expect(scale.levelOf(null), 0);
    });

    test('53 Monday-to-Sunday columns ending with the current week', () {
      final grid = heatmapGrid(now: now, calendar: madrid);
      expect(grid.today, '2026-09-30');
      expect(grid.weeks, hasLength(53));
      expect(grid.weeks.last.first, '2026-09-28');
      expect(grid.weeks.last.last, '2026-10-04');
      expect(grid.weeks.first.first, '2025-09-29');
      expect(grid.weeks.every((w) => w.length == 7 && weekdayOf(w.first) == 1), isTrue);
      expect(grid.isFuture('2026-10-01'), isTrue);
      expect(grid.isFuture('2026-09-30'), isFalse);
      // A column is labelled when its Monday is one of the first 7 days of a new month, and never
      // in the last two columns.
      expect(grid.monthLabels.first, isNull); // 29 Sep 2025
      expect(grid.monthLabels[1], 10); // 6 Oct 2025
      expect(grid.monthLabels[51], isNull);
      expect(grid.monthLabels[52], isNull);
      final labelled = [
        for (var i = 0; i < 53; i++)
          if (grid.monthLabels[i] != null) grid.monthLabels[i],
      ];
      expect(labelled, [10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });
  });

  group('windows', () {
    final workouts = [session('2026-09-27'), session('2026-09-28'), session('2026-09-01'), session('2026-06-01')];

    test('muscle balance: the week is the current ISO week, not the last 7 days', () {
      List<String> dates(int window) => [
        for (final w in muscleBalanceWorkouts(workouts, window, now: now, calendar: madrid)) w.d,
      ];
      expect(dates(7), ['2026-09-28']);
      expect(dates(30), ['2026-09-27', '2026-09-28', '2026-09-01']);
      expect(dates(90), ['2026-09-27', '2026-09-28', '2026-09-01']);
      expect(dates(0), hasLength(4));
    });

    test('hard sets are offered only when the window holds one', () {
      final rated = session(
        '2026-09-28',
        entries: [
          {
            'id': '0025',
            'sets': [
              {'w': 60, 'r': 8, 'rpe': 8, 'done': true},
            ],
          },
        ],
      );
      expect(hasHardSets([rated]), isTrue);
      expect(hasHardSets(workouts), isFalse);
    });

    test('body weight: by `t`, or local noon of a date without one', () {
      final entries = [
        BodyWeight(d: '2026-08-01', w: 80, t: madrid.noonOf('2026-08-01')),
        BodyWeight(d: '2026-09-02', w: 79.4, t: 0),
        BodyWeight(d: '2026-09-29', w: 78.9, t: madrid.noonOf('2026-09-29')),
      ];
      expect(bodyWeightsWithinDays(entries, 30, now: now, calendar: madrid).map((b) => b.d), [
        '2026-09-02',
        '2026-09-29',
      ]);
      expect(bodyWeightsWithinDays(entries, 0, now: now, calendar: madrid), hasLength(3));
      final tiles = statsTiles([session('2026-09-28'), session('2026-08-30')], entries, now: now, calendar: madrid);
      expect(tiles.workouts, 2);
      expect(tiles.thisMonth, 1);
      expect(tiles.streakWeeks, 1);
      expect(tiles.weightChange30d, closeTo(-0.5, 1e-9));
      expect(statsTiles(const [], entries.take(1).toList(), now: now, calendar: madrid).weightChange30d, isNull);
    });
  });

  group('home', () {
    final plan = PlanDoc(
      routines: [
        Routine(id: 'r1', name: 'Empuje'),
        Routine(id: 'r2', name: 'Tirón'),
      ],
      week: {'1': 'r1', '3': 'r2', '5': 'gone', '6': ''},
    );
    final schedule = ScheduleDoc(dayPlan: {'2026-10-01': 'r1', '2026-10-02': 'rest'});
    final workouts = [session('2026-09-28')];

    test('workouts this week and planned days', () {
      expect(workoutsThisWeek(workouts, now: now, calendar: madrid), 1);
      expect(plannedPerWeek(plan), 3);
      expect(weekDates('2026-09-30'), [
        '2026-09-28', '2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04', //
      ]);
    });

    test('week strip dots', () {
      DayMark mark(String iso) => dayMark(iso, workouts: workouts, plan: plan, schedule: schedule);
      expect(mark('2026-09-28'), DayMark.done);
      expect(mark('2026-09-30'), DayMark.planned);
      expect(mark('2026-10-01'), DayMark.rescheduled);
      expect(mark('2026-10-02'), DayMark.none); // Friday rescheduled to rest
      expect(mark('2026-09-29'), DayMark.none);
      expect(mark('2026-10-03'), DayMark.none);
    });
  });

  group('exercise progress', () {
    final state = TrainingState(
      catalog: indexWith(),
      workouts: [
        session(
          '2026-09-14',
          entries: [
            {
              'id': '0025',
              'target': {'mode': 'reps'},
              'topW': 85,
              'sets': [
                {'w': 80, 'r': 5, 'rir': 2, 'done': true},
                {'w': 90, 'r': 5, 'done': false},
              ],
            },
            {
              'id': '0001',
              'sets': [
                {'w': 0, 'r': 20, 'done': true},
              ],
            },
            {
              'id': 'gone',
              'sets': [
                {'w': 10, 'r': 5, 'done': true},
              ],
            },
          ],
        ),
        session(
          '2026-09-21',
          entries: [
            {
              'id': '0025',
              'target': {'mode': 'reps'},
              'sets': [
                {'w': 82.5, 'r': 5, 'rpe': 9, 'done': true},
              ],
            },
            {
              'id': '0001',
              'target': {'mode': 'time'},
              'sets': [
                {'sec': 60, 'w': 0, 'done': true},
              ],
            },
          ],
        ),
      ],
    );

    test('lists exercises that still resolve, by name', () {
      expect(progressExercises(state), ['0001', '0025']); // "3/4 sit-up" < "barbell bench press"
    });

    test('the latest mode decides the metric; sessions scoring 0 are left out', () {
      expect(latestModeOf(state, '0001'), 'time');
      expect(latestModeOf(state, '0025'), 'reps');
      expect(latestModeOf(state, '3220'), 'cardio');
      final holds = progressSeries(state, '0001', latestModeOf(state, '0001'));
      expect(holds.map((p) => p.y), [60]); // the reps session has no seconds
      final bench = progressSeries(state, '0025', 'reps');
      expect(bench.map((p) => p.y), [85, 82.5]); // a confirmed topW counts for reps
      expect(bench.map((p) => p.avgRir), [2, 1]);
      expect(bench.first.sets, hasLength(1));
      expect(bench.last.t, madrid.noonOf('2026-09-21'));
    });
  });
}
