import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

RoutineExercise? _cfg(Object? json) => json == null ? null : RoutineExercise.fromJson(json);

/// A session carrying only the fields the stall counters read.
RepsSession _session(Object? json) {
  final m = asMap(json);
  return RepsSession(
    goal: 0,
    reps: const [],
    weight: asNum(m['weight']) ?? 0,
    low: asNum(m['low']) ?? 0,
    amrap: 0,
    ok: m['ok'] == true,
  );
}

void main() {
  final fixture = loadFixture('engine/progression.json');

  test('constants match the fixture', () {
    final c = asMap(fixture['constants']);
    expectJson(policies, c['POLICIES']);
    expectJson(policiesFor, c['POLICIES_FOR']);
    expectJson(deloadAfter, c['DELOAD_AFTER']);
    expect(defaultSecIncrement, c['DEFAULT_SEC_INCREMENT']);
  });

  fixtureGroups('engine/progression.json', {
    'readSession': (a, expected, _) => expectJson(
      readSession(
        indexWith(),
        a['entry'] == null ? null : WorkoutEntry.fromJson(a['entry']),
        _cfg(a['fallback']),
      ).toJson(),
      expected,
    ),
    'sessionsFor': (a, expected, _) => expectJson([
      for (final s in sessionsFor(stateFrom(a['state']), a['exId'] as String, _cfg(a['fallback']))) s.toJson(),
    ], expected),
    'stallCount': (a, expected, _) =>
        expect(stallCount([for (final s in asList(a['sessions'])) _session(s)]), expected),
    'doubleStallCount': (a, expected, _) =>
        expect(doubleStallCount([for (final s in asList(a['sessions'])) _session(s)]), expected),
    'policyFor': (a, expected, _) => expect(
      policyFor(
        indexWith(),
        _cfg(a['cfg']),
        a['routine'] == null ? null : Routine.fromJson(a['routine']),
        a['mode'] as String?,
      ),
      expected,
    ),
    'defaultIncrement': (a, expected, _) =>
        expect(defaultIncrement(indexWith(a['customEx']), a['exId'] as String, a['unit'] as String), expected),
    'nextPrescription': (a, expected, _) {
      final p = nextPrescription(
        stateFrom(a['state']),
        RoutineExercise.fromJson(a['cfg']),
        a['routine'] == null ? null : Routine.fromJson(a['routine']),
      );
      expectJson(p.toJson(), expected);
      // Every template the engine emits has a Spanish rendering.
      if (p.why != null) expect(whyText(p.why), isNot(contains('{')));
    },
  });
}
