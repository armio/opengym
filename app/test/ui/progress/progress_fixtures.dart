import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/dates.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import '../../widgets/test_app.dart';

/// A finished workout on [d] (local 18:00) lasting [minutes], its volume computed.
Workout progressWorkout(
  String id,
  String d, {
  List<WorkoutEntry> entries = const [],
  int minutes = 55,
  String? routineId,
  String name = 'Entreno',
  List<String> prs = const [],
  String? rating,
  String? note,
  int hour = 18,
}) {
  final day = parseIsoDate(d)!;
  final start = DateTime(day.year, day.month, day.day, hour).millisecondsSinceEpoch;
  final w = Workout(
    id: id,
    d: d,
    start: start,
    end: start + minutes * 60000,
    routineId: routineId,
    name: name,
    entries: [...entries],
    prs: [...prs],
    rating: rating,
    note: note,
  );
  return w..vol = workoutVolume(w);
}

/// A reps entry of [sets] done sets at [w] × [r], optionally rated with [rir].
WorkoutEntry repsEntry(String id, num w, {int sets = 3, num r = 8, num? rir, num? rpe, num? topW}) => WorkoutEntry(
  id: id,
  sets: [for (var i = 0; i < sets; i++) SetRecord(w: w, r: r, rir: rir, rpe: rpe, done: true)],
  topW: topW,
  target: {'id': id, 'sets': sets, 'reps': r, 'weight': w, 'mode': 'reps'},
);

/// A timed entry of done holds of [sec] seconds.
WorkoutEntry timeEntry(String id, num sec, {int sets = 3}) => WorkoutEntry(
  id: id,
  sets: [for (var i = 0; i < sets; i++) SetRecord(sec: sec, w: 0, done: true)],
  target: {'id': id, 'sets': sets, 'sec': sec, 'weight': 0, 'mode': 'time'},
);

/// Three routines and [weeks] weeks of Monday / Wednesday / Friday training ending on
/// 2026-09-30 (the test clock's today), with steady progression, ratings in the last eight
/// weeks when [effort], weigh-ins drifting towards a 75 kg goal when [bodyWeight].
AppState seededProgressApp({int weeks = 16, bool effort = true, bool bodyWeight = true}) {
  final app = testAppState();
  app.updatePlan((p) {
    p.routines.addAll([
      Routine(
        id: 'r1',
        name: 'Empuje',
        emoji: 'barbell',
        ex: [
          RoutineExercise(id: '0025', sets: 3, reps: 8, weight: 60),
          RoutineExercise(id: '0426', sets: 3, reps: 10, weight: 14),
        ],
      ),
      Routine(
        id: 'r2',
        name: 'Tirón',
        emoji: 'pullup',
        ex: [
          RoutineExercise(id: '0027', sets: 3, reps: 8, weight: 50),
          RoutineExercise(id: '2135', sets: 3, sec: 45, mode: 'time'),
        ],
      ),
      Routine(
        id: 'r3',
        name: 'Pierna',
        emoji: 'legs',
        ex: [
          RoutineExercise(id: '0043', sets: 4, reps: 6, weight: 80),
          RoutineExercise(id: '0085', sets: 3, reps: 10, weight: 60),
        ],
      ),
    ]);
    p.week.addAll({'1': 'r1', '3': 'r2', '5': 'r3'});
  });
  if (effort) app.updateSettings((s) => s.setEffortScale('rir'));
  if (bodyWeight) app.updateSettings((s) => s.targetW = 75);

  final lastMonday = mondayOf('2026-09-30');
  var n = 0;
  for (var week = weeks - 1; week >= 0; week--) {
    final monday = addDays(lastMonday, -7 * week);
    final k = weeks - 1 - week; // 0 = oldest week
    final rated = effort && week < 8;
    num? rir(int i) => rated ? [3, 2, 1, 2, 4, 0][(k + i) % 6] : null;
    final days = [
      (
        0,
        'r1',
        'Empuje',
        [repsEntry('0025', 60 + 2.5 * k, rir: rir(0)), repsEntry('0426', 14 + (k ~/ 3) * 2, r: 10, rir: rir(1))],
      ),
      (2, 'r2', 'Tirón', [repsEntry('0027', 50 + 2.5 * k, rir: rir(2)), timeEntry('2135', 40 + 5 * (k ~/ 2))]),
      (
        4,
        'r3',
        'Pierna',
        [repsEntry('0043', 80 + 2.5 * k, sets: 4, r: 6, rir: rir(3)), repsEntry('0085', 60 + 2.5 * k, r: 10)],
      ),
    ];
    for (final (offset, routine, name, entries) in days) {
      final d = addDays(monday, offset);
      if (d.compareTo('2026-09-30') > 0) continue;
      // A missed session now and then keeps the weeks uneven.
      if ((k * 3 + offset) % 7 == 5) continue;
      n++;
      app.saveWorkout(
        progressWorkout(
          'w$n',
          d,
          entries: entries,
          minutes: 40 + (n * 7) % 35,
          routineId: routine,
          name: name,
          prs: [if (n % 4 == 0) entries.first.id],
          rating: switch (n % 5) {
            0 => 'hard',
            1 => 'right',
            2 => 'easy',
            _ => null,
          },
          note: n % 9 == 0 ? 'Buenas sensaciones, la última serie costó.' : null,
        ),
      );
    }
  }
  if (bodyWeight) {
    for (var i = 0; i < 40; i++) {
      final d = addDays('2026-09-30', -3 * i);
      final day = parseIsoDate(d)!;
      final t = DateTime(day.year, day.month, day.day, 8).millisecondsSinceEpoch;
      app.setBodyWeight(round1(78 + i * 0.06 + (i % 3) * 0.2), date: d, t: t);
    }
  }
  return app;
}

/// Exercise thumbnails cache their images under path_provider's directories; tests have no
/// plugin, so point it at a temporary directory.
void mockPathProvider(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final dir = Directory.systemTemp.createTempSync('progress_test');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => dir.path);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
}
