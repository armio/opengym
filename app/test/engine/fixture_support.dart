/// Shared plumbing for the fixture-driven engine tests: loads the vectors of
/// `docs/flutter-cloudflare/fixtures` (see its README), decodes the `$js` markers, pins the
/// fixtures' clock and zone, and compares results the way the README prescribes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/dates.dart';
import 'package:opengym/data/library.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The repository root, found by walking up from the test's working directory.
final Directory repoRoot = () {
  var dir = Directory.current.absolute;
  while (!Directory('${dir.path}/docs/flutter-cloudflare/fixtures').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('docs/flutter-cloudflare/fixtures not found above ${Directory.current.path}');
    }
    dir = parent;
  }
  return dir;
}();

/// A fixture file, relative to `docs/flutter-cloudflare/fixtures`.
JsonMap loadFixture(String relativePath) =>
    jsonDecode(File('${repoRoot.path}/docs/flutter-cloudflare/fixtures/$relativePath').readAsStringSync()) as JsonMap;

/// Replaces the `{"$js": …}` markers with Dart values (`undefined` reads as null).
Object? fromJs(Object? value) {
  if (value is Map) {
    if (value.length == 1 && value.containsKey(r'$js')) {
      return switch (value[r'$js']) {
        'NaN' => double.nan,
        'Infinity' => double.infinity,
        '-Infinity' => double.negativeInfinity,
        _ => null,
      };
    }
    return <String, dynamic>{for (final e in value.entries) '${e.key}': fromJs(e.value)};
  }
  if (value is List) return [for (final v in value) fromJs(v)];
  return value;
}

/// A [LocalCalendar] pinned to one IANA zone, whatever the host's.
class ZonedCalendar extends LocalCalendar {
  ZonedCalendar(String zone) : location = _location(zone);

  final tz.Location location;

  static tz.Location _location(String zone) {
    tzdata.initializeTimeZones();
    return tz.getLocation(zone);
  }

  @override
  String dateOf(int epochMs) {
    final t = tz.TZDateTime.fromMillisecondsSinceEpoch(location, epochMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  @override
  int noonOf(String iso) {
    final d = parseIsoDate(iso)!;
    return tz.TZDateTime(location, d.year, d.month, d.day, 12).millisecondsSinceEpoch;
  }
}

/// The fixtures' zone.
final madrid = ZonedCalendar('Europe/Madrid');

/// The real exercise library (`assets/exercises.json`).
final ExerciseLibrary testLibrary = ExerciseLibrary.fromJson(
  jsonDecode(File('${repoRoot.path}/app/assets/exercises.json').readAsStringSync()) as List<dynamic>,
);

/// The library plus [customEx] (custom exercise JSON) as the engine sees it.
ExerciseIndex indexWith([Object? customEx]) => CatalogExerciseIndex(
  ExerciseCatalog(testLibrary, [
    for (final c in asList(customEx))
      if (c is Map) CustomExercise.fromJson(c),
  ]),
);

/// A fixture workout; one without `start` sits at local noon of `d` in the fixtures' zone.
Workout workoutFrom(Object? json) {
  final m = asMap(json);
  if (m['start'] == null) m['start'] = madrid.noonOf(m['d'] as String);
  return Workout.fromJson(m);
}

/// The workouts of a fixture state.
List<Workout> workoutsFrom(Object? list) => [for (final w in asList(list)) workoutFrom(w)];

/// A [TrainingState] from a fixture `state` (plus any `customEx` passed alongside).
TrainingState stateFrom(Object? json, {Object? customEx}) {
  final s = asMap(json);
  return TrainingState(
    catalog: indexWith([...asList(s['customEx']), ...asList(customEx)]),
    workouts: workoutsFrom(s['workouts']),
    unit: asString(s['unit']) ?? 'kg',
    exWeights: {for (final e in asMap(s['exWeights']).entries) e.key: ExWeight.fromJson(e.value)},
  );
}

/// The instant a vector runs at: its own `now`, else the file's clock.
DateTime nowOf(JsonMap fixture, JsonMap vector) =>
    DateTime.fromMillisecondsSinceEpoch(asInt(vector['now']) ?? asInt(asMap(fixture['clock'])['now'])!);

/// The first difference between [actual] and [expected] as a path and message, or null.
///
/// Deep equality where an absent key equals null, key order is ignored, numbers compare by value
/// with a 1e-9 relative tolerance, and NaN equals NaN.
String? jsonDiff(Object? actual, Object? expected, [String path = r'$']) {
  if (expected is Map) {
    if (actual is! Map) return '$path: expected an object, got ${jsonEncodeSafe(actual)}';
    for (final key in {...expected.keys, ...actual.keys}) {
      final diff = jsonDiff(actual[key], expected[key], '$path.$key');
      if (diff != null) return diff;
    }
    return null;
  }
  if (expected is List) {
    if (actual is! List) return '$path: expected a list, got ${jsonEncodeSafe(actual)}';
    if (actual.length != expected.length) {
      return '$path: expected ${expected.length} items, got ${actual.length}: ${jsonEncodeSafe(actual)}';
    }
    for (var i = 0; i < expected.length; i++) {
      final diff = jsonDiff(actual[i], expected[i], '$path[$i]');
      if (diff != null) return diff;
    }
    return null;
  }
  if (expected is num && actual is num) {
    if (expected.isNaN && actual.isNaN) return null;
    if (actual == expected) return null;
    final scale = expected.abs() > 1 ? expected.abs() : 1;
    return (actual - expected).abs() <= 1e-9 * scale ? null : '$path: expected $expected, got $actual';
  }
  return actual == expected ? null : '$path: expected ${jsonEncodeSafe(expected)}, got ${jsonEncodeSafe(actual)}';
}

String jsonEncodeSafe(Object? v) {
  try {
    return jsonEncode(v);
  } catch (_) {
    return '$v';
  }
}

/// Expects [actual] to equal [expected] under [jsonDiff].
void expectJson(Object? actual, Object? expected) {
  final diff = jsonDiff(actual, expected);
  if (diff != null) fail(diff);
}

/// Checks one vector: decoded `args`, decoded `expected`, and the raw vector (for `now`, flags).
typedef VectorCheck = void Function(JsonMap args, Object? expected, JsonMap vector);

/// Registers a test per vector of every group in [file], and a test that every group of the file
/// has a check — so a group added to the fixtures cannot be skipped silently. [skip] maps
/// `'<group>/<vector name>'` to the reason a vector cannot apply to the typed port.
void fixtureGroups(String file, Map<String, VectorCheck> checks, {Map<String, String> skip = const {}}) {
  final fixture = loadFixture(file);
  final groups = asMap(fixture['groups']);
  test('$file: every group has a check', () => expect(checks.keys.toSet(), groups.keys.toSet()));
  for (final entry in groups.entries) {
    final check = checks[entry.key];
    if (check == null) continue;
    group(entry.key, () {
      final vectors = asList(asMap(entry.value)['vectors']);
      for (var i = 0; i < vectors.length; i++) {
        final vector = asMap(vectors[i]);
        test('#$i ${vector['name']}', skip: skip['${entry.key}/${vector['name']}'], () {
          check(asMap(fromJs(vector['args'])), fromJs(vector['expected']), vector);
        });
      }
    });
  }
}
