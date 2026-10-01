import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

SetRecord? _set(Object? json) => json == null ? null : SetRecord.fromJson(json);

void main() {
  final fixture = loadFixture('engine/effort.json');
  DateTime now(JsonMap vector) => nowOf(fixture, vector);

  test('constants match the fixture', () {
    final c = asMap(fixture['constants']);
    expect(hardRir, c['HARD_RIR']);
    expect(minRated, c['MIN_RATED']);
    expect(effortBuckets, c['BUCKETS']);
  });

  fixtureGroups('engine/effort.json', {
    'rirOf': (a, expected, _) => expect(rirOf(_set(a['set'])), expected),
    'toScale': (a, expected, _) => expect(toScale(a['kind'] as String, a['rir'] as num?), expected),
    'displayScale': (a, expected, _) =>
        expect(displayScale(Settings.fromJson(a['state']), workoutsFrom(asMap(a['state'])['workouts'])), expected),
    'avgRir': (a, expected, _) =>
        expect(avgRir(a['sets'] == null ? null : [for (final s in asList(a['sets'])) SetRecord.fromJson(s)]), expected),
    'effortSummary': (a, expected, v) {
      final s = effortSummary(workoutsFrom(asMap(a['state'])['workouts']), a['days'] as int, now: now(v));
      expectJson({'done': s.done, 'rated': s.rated, 'hard': s.hard, 'avg': s.avg, 'hardPct': s.hardPct}, expected);
    },
    'hasEffort': (a, expected, _) => expect(hasEffort(workoutsFrom(asMap(a['state'])['workouts'])), expected),
    'effortWeeks': (a, expected, v) => expectJson([
      for (final w in effortWeeks(
        workoutsFrom(asMap(a['state'])['workouts']),
        a['days'] as int,
        now: now(v),
        calendar: madrid,
      ))
        {'t': w.t, 'rir': w.rir, 'n': w.n, 'sets': w.sets},
    ], expected),
    'effortHistogram': (a, expected, v) => expectJson([
      for (final b in effortHistogram(workoutsFrom(asMap(a['state'])['workouts']), a['days'] as int, now: now(v)))
        {'rir': b.rir, 'tail': b.tail, 'n': b.n, 'pct': b.pct},
    ], expected),
    'isHardSet': (a, expected, _) => expect(isHardSet(SetRecord.fromJson(a['set'])), expected),
  });
}
