import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

void main() {
  final dates = loadFixture('engine/dates.json');

  fixtureGroups('engine/dates.json', {
    'weekKey': (a, expected, _) => expect(weekKey(a['date'] as String), expected),
    'streakWeeks': (a, expected, v) => expect(
      streakWeeks(workoutsFrom(asMap(a['state'])['workouts']), now: nowOf(dates, v), calendar: madrid),
      expected,
    ),
    'fmtSec': (a, expected, _) => expect(fmtSec(a['sec'] as num?), expected),
    'fmtDur': (a, expected, _) => expect(fmtDur(a['ms'] as num), expected),
    'durPart': (a, expected, _) => expect(durPart(a['ms'] as num), expected),
    'sortWorkouts': (a, expected, _) {
      expect(a['tz'], 'Europe/Madrid', reason: 'the test calendar is pinned to Madrid');
      expect([for (final w in sortWorkouts(workoutsFrom(a['workouts']))) w.id], expected);
    },
  });

  fixtureGroups('engine/stats.json', {
    'heatmap': (a, expected, _) {
      final scale = HeatmapScale.fromMinutes([for (final d in asList(a['days'])) asMap(d)['min'] as num]);
      final levels = [
        for (final probe in asList(a['probes']))
          probe == null ? 0 : scale.levelOf(HeatmapDay(workouts: 1, volume: 0, minutes: probe as int)),
      ];
      expectJson({'t1': scale.t1, 't2': scale.t2, 't3': scale.t3, 'levels': levels}, expected);
    },
  });
}
