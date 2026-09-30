import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

MuscleLoad _load(Object? json) => {for (final e in asMap(json).entries) e.key: e.value as num};

void main() {
  final fixture = loadFixture('engine/muscles.json');

  test('constants match the fixture', () {
    expectJson(muscles, asMap(fixture['constants'])['MUSCLES']);
    expect(muscleNames.keys.toSet(), muscles.toSet());
  });

  fixtureGroups('engine/muscles.json', {
    'musclesOf': (a, expected, _) {
      final index = indexWith(a['customEx']);
      expectJson(musclesOf(index.lookup(a['exId'] as String)), expected);
    },
    'loadOf': (a, expected, _) => expectJson(
      loadOf(indexWith(a['customEx']), [
        for (final i in asList(a['items'])) (id: asMap(i)['id'] as String, sets: asMap(i)['sets'] as num),
      ]),
      expected,
    ),
    'loadOfWorkouts': (a, expected, _) => expectJson(
      loadOfWorkouts(
        indexWith(a['customEx']),
        workoutsFrom(a['workouts']),
        pick: a['hardOnly'] == true ? isHardSet : null,
      ),
      expected,
    ),
    'loadOfRoutine': (a, expected, _) =>
        expectJson(loadOfRoutine(indexWith(), Routine.fromJson(a['routine'])), expected),
    'levelsOf': (a, expected, _) => expectJson(levelsOf(_load(a['load'])), expected),
    'rankOf': (a, expected, _) {
      final rank = rankOf(_load(a['load']));
      expectJson({'worked': rank.worked, 'missed': rank.missed}, expected);
    },
  });
}
