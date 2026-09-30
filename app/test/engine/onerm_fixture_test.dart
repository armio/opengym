import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

JsonMap? _best(BestSet? b) => b == null ? null : {'est': b.est, 'w': b.w, 'r': b.r};

void main() {
  final fixture = loadFixture('engine/onerm.json');

  test('constants match the fixture', () {
    final c = asMap(fixture['constants']);
    expect(repCap, c['REP_CAP']);
    expect(defaultFormula, c['DEFAULT_FORMULA']);
    expect(formulas.keys.toList(), c['FORMULAS']);
  });

  fixtureGroups(
    'engine/onerm.json',
    {
      'estimate1RM': (a, expected, _) => expect(
        a['formula'] == null ? estimate1RM(a['w'], a['r']) : estimate1RM(a['w'], a['r'], a['formula'] as String),
        expected,
      ),
      'bestSetOf': (a, expected, _) =>
          expectJson(_best(bestSetOf(a['entry'] == null ? null : WorkoutEntry.fromJson(a['entry']).sets)), expected),
      'e1rmSeries': (a, expected, _) => expectJson([
        for (final p in e1rmSeries(workoutsFrom(asMap(a['state'])['workouts']), a['exId'] as String))
          {'t': p.t, 'd': p.d, 'y': p.y, 'w': p.w, 'r': p.r},
      ], expected),
      'best1RM': (a, expected, _) {
        final b = best1RM(workoutsFrom(asMap(a['state'])['workouts']), a['exId'] as String);
        expectJson(b == null ? null : {..._best(b)!, 'd': b.d, 't': b.t}, expected);
      },
      'is1RMRecord': (a, expected, _) {
        final r = is1RMRecord(
          workoutsFrom(asMap(a['state'])['workouts']),
          a['exId'] as String,
          WorkoutEntry.fromJson(a['entry']).sets,
        );
        expectJson(r == null ? null : {..._best(r)!, 'prev': r.prev}, expected);
      },
    },
    skip: {
      'bestSetOf/fractional reps are rounded in the result':
          'numeric strings in a set: the typed SetRecord keeps numbers only, so "100" never reaches the engine',
    },
  );
}
