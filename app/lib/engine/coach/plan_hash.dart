/// The plan fingerprint (specs/coach.md §7.1, contract §5.4), byte-identical to the Worker's:
/// a proposal stores the hash of the plan Claude read, and the app compares it with the live
/// plan for the "Tu plan cambió desde que Claude lo revisó" banner.
///
/// It runs on the plan doc's JSON with JavaScript semantics (`||`, `String(n)`,
/// `JSON.stringify`), exactly as the original did, so odd stored values hash the same on both
/// sides.
library;

import '../../data/models/json.dart';
import '../../data/models/plan.dart';
import '../catalog.dart';
import '../history.dart';
import '../js.dart';

const _weekdays = [1, 2, 3, 4, 5, 6, 0];

List<dynamic> _listOf(Object? value) => value is List ? value : const [];

Map<dynamic, dynamic> _mapOf(Object? value) => value is Map ? value : const {};

/// `canonicalPlan`: the routines and week of [plan] (plan doc JSON), mode-aware, every absent
/// value written out as 0 or `''` so "no weight" and "0 kg" hash alike. [catalog] resolves modes
/// by body part and must know the plan's custom exercises.
JsonMap canonicalPlan(Map<dynamic, dynamic> plan, ExerciseIndex catalog) {
  final week = _mapOf(plan['week']);
  return {
    'routines': [
      for (final r in _listOf(plan['routines']))
        {
          'id': _mapOf(r)['id'],
          'name': jsOr(_mapOf(r)['name'], ''),
          'prog': jsOr(_mapOf(r)['prog'], ''),
          'ex': [for (final e in _listOf(_mapOf(r)['ex'])) _canonicalExercise(_mapOf(e), catalog)],
        },
    ],
    'week': {
      for (final d in _weekdays)
        if (jsTruthy(week['$d'])) '$d': week['$d'],
    },
  };
}

JsonMap _canonicalExercise(Map<dynamic, dynamic> e, ExerciseIndex catalog) {
  final id = e['id'];
  final mode = modeFor(catalog, mode: e['mode'], id: id is String ? id : null);
  return {
    'id': id,
    'mode': mode,
    'sets': jsOr(e['sets'], 0),
    'reps': mode == ExerciseMode.reps ? jsOr(e['reps'], 0) : 0,
    'sec': mode == ExerciseMode.time ? jsOr(e['sec'], 0) : 0,
    'min': mode == ExerciseMode.cardio ? jsOr(e['min'], 0) : 0,
    'speed': mode == ExerciseMode.cardio ? jsOr(e['speed'], 0) : 0,
    'weight': mode == ExerciseMode.cardio ? 0 : jsOr(e['weight'], 0),
    'prog': jsOr(e['prog'], ''),
    'inc': jsOr(e['inc'], 0),
    'repsMin': jsOr(e['repsMin'], 0),
    'sg': jsOr(e['sg'], ''),
  };
}

const _exerciseFields = ['id', 'mode', 'sets', 'reps', 'sec', 'min', 'speed', 'weight', 'prog', 'inc', 'repsMin', 'sg'];

/// The exact string [hashPlan] iterates over (UTF-16 code units).
String canonString(JsonMap canonical) {
  final week = _mapOf(canonical['week']);
  final keys = [for (final k in week.keys) '$k']..sort();
  return jsonStringify({
    'routines': [
      for (final r in _listOf(canonical['routines']))
        [
          _mapOf(r)['id'],
          _mapOf(r)['name'],
          _mapOf(r)['prog'],
          [
            for (final e in _listOf(_mapOf(r)['ex']))
              [for (final f in _exerciseFields) jsString(_mapOf(e)[f], nullText: '')].join(':'),
          ],
        ],
    ],
    'week': [for (final k in keys) '$k=${jsString(week[k])}'],
  });
}

/// Two 32-bit FNV-1a-style lanes over [canonString], as 16 lowercase hex digits.
String hashPlan(JsonMap canonical) {
  final canon = canonString(canonical);
  var h1 = 0x811c9dc5;
  var h2 = 0x01000193;
  for (var i = 0; i < canon.length; i++) {
    final c = canon.codeUnitAt(i);
    h1 = imul32(h1 ^ c, 0x01000193);
    h2 = imul32(h2 ^ ((c << 3) | (i & 7)), 0x85ebca6b);
  }
  return h1.toRadixString(16).padLeft(8, '0') + h2.toRadixString(16).padLeft(8, '0');
}

/// The fingerprint of a plan doc given as JSON; its own custom exercises are looked up first.
String planHashOfJson(Map<dynamic, dynamic> plan, ExerciseIndex library) {
  final customs = [
    for (final c in _listOf(plan['customEx']))
      if (c is Map) CustomExercise.fromJson(c),
  ];
  return hashPlan(canonicalPlan(plan, library.withCustoms(customs)));
}

/// `planHash(S)`: the fingerprint of [plan], as the Worker computes it for a proposal.
String planHash(PlanDoc plan, ExerciseIndex library) => planHashOfJson(plan.toJson(), library);
