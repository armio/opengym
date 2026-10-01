import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

RoutineExercise? _cfg(Object? json) => json == null ? null : RoutineExercise.fromJson(json);

List<SetRecord> _sets(Object? json) => [for (final s in asList(json)) SetRecord.fromJson(s)];

void main() {
  fixtureGroups('engine/history.json', {
    'modeOf': (a, expected, _) => expect(modeOf(indexWith(a['customEx']), _cfg(a['cfg'])), expected),
    'isTimed': (a, expected, _) => expect(isTimed(indexWith(), _cfg(a['cfg'])), expected),
    'effortOf': (a, expected, _) =>
        expect(effortOf(a['settings'] == null ? null : Settings.fromJson(a['settings'])), expected),
    'stepEffort': (a, expected, _) =>
        expect(stepEffort(a['kind'] as String?, a['cur'] as num?, a['dir'] as int), expected),
    'stepEffortSequence': (a, expected, _) {
      num? value = a['start'] as num?;
      for (final dir in asList(a['dirs'])) {
        value = stepEffort(a['kind'] as String?, value, dir as int);
      }
      expect(value, expected);
    },
    'capEffort': (a, expected, _) => expect(capEffort(a['kind'] as String?, a['value'] as num?), expected),
    'defaultConfig': (a, expected, _) {
      final cfg = defaultConfig(indexWith(), a['id'] as String, a['mode'] as String?);
      expect(cfg.id, a['id']);
      expectJson(cfg.toJson()..remove('id'), expected);
    },
    'cleanupSg': (a, expected, _) {
      final input = [for (final e in asList(a['ex'])) asMap(e)];
      final ex = [for (final e in input) RoutineExercise.fromJson(e)];
      cleanupSg(ex);
      // Compare only the keys the input had: the model adds defaults (`id`, `sets`) of its own.
      expectJson([
        for (var i = 0; i < ex.length; i++) {for (final key in input[i].keys) key: ex[i].toJson()[key]},
      ], expected);
    },
    'supersetUnits': (a, expected, _) =>
        expectJson(supersetUnits([for (final i in asList(a['items'])) asString(asMap(i)['sg'])]), expected),
    'lastEntryFor': (a, expected, _) {
      final last = lastEntryFor(stateFrom(a['state']).workouts, a['exId'] as String);
      expectJson(
        last == null
            ? null
            : {
                'd': last.d,
                'sets': [for (final s in last.sets) s.toJson()],
                'target': last.target,
              },
        expected,
      );
    },
    'bestWeightFor': (a, expected, _) => expect(bestWeightFor(stateFrom(a['state']), a['exId'] as String), expected),
    'effectiveRoutineId': (a, expected, _) => expect(
      effectiveRoutineId(PlanDoc.fromJson(a['plan']), ScheduleDoc.fromJson(a['plan']), a['date'] as String),
      expected,
    ),
    'effectiveRoutine': (a, expected, _) => expectJson(
      effectiveRoutine(PlanDoc.fromJson(a['plan']), ScheduleDoc.fromJson(a['plan']), a['date'] as String)?.toJson(),
      expected,
    ),
    'buildSets': (a, expected, _) => expectJson([
      for (final s in buildSets(stateFrom(a['state']), RoutineExercise.fromJson(a['cfg']))) s.toJson(),
    ], expected),
    'applyPrescription': (a, expected, vector) {
      final sets = _sets(a['sets']);
      final p = a['prescription'] == null ? null : Prescription.fromJson(a['prescription']);
      final out = applyPrescription(sets, p);
      expectJson([for (final s in out) s.toJson()], expected);
      expect(identical(out, sets), vector['sameInstance'], reason: 'sameInstance');
    },
    'workoutVolume': (a, expected, _) =>
        expect(workoutVolume(workoutFrom({'d': '2026-01-01', ...asMap(a['workout'])})), expected),
    'setsDone': (a, expected, _) =>
        expect(setsDone(workoutFrom({'d': '2026-01-01', ...asMap(a['workout'])})), expected),
    'linkSuperset': (a, expected, _) {
      final original = [for (final e in asList(a['ex'])) RoutineExercise.fromJson(e)];
      final oldTags = {for (final e in original) ?e.sg};
      final plan = PlanDoc(
        routines: [Routine(id: 'r1', name: 'R', ex: original)],
      );
      for (final link in asList(a['links'])) {
        final pair = asList(link);
        applyChange(
          plan,
          {
            'id': 'c1',
            'type': 'superset',
            'target': {'routineId': 'r1', 'exId': pair[0]},
            'after': {'link': true, 'with': pair[1]},
          },
          catalog: indexWith(),
          now: DateTime(2026, 9, 30),
        );
      }
      final ex = plan.routines.single.ex;
      // Name each tag by order of first appearance so the result compares with the letters.
      final letters = <String, String>{};
      for (final e in ex) {
        if (e.sg != null) letters.putIfAbsent(e.sg!, () => String.fromCharCode(0x41 + letters.length));
      }
      expectJson({
        'ids': [for (final e in ex) e.id],
        'sg': [for (final e in ex) e.sg == null ? null : letters[e.sg]],
      }, expected);
      for (final tag in letters.keys) {
        expect(tag, startsWith('sg'));
        expect(oldTags, isNot(contains(tag)), reason: 'tags are fresh');
      }
    },
  });
}
