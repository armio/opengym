/// Finishing a workout (specs/engine.md §8.1–§8.2, specs/ui.md §5.9–§5.11): the stored record,
/// load and e1RM records, and the working-weight memory. Load records and working weights only
/// count entries logged in reps mode (engine-Q5).
library;

import 'dart:math';

import '../data/models/active_workout.dart';
import '../data/models/body_weight.dart';
import '../data/models/json.dart';
import '../data/models/workout.dart';
import 'history.dart';
import 'js.dart';
import 'onerm.dart';
import 'training_state.dart';

/// An estimated-1RM record set in the finished session.
class E1rmRecord {
  const E1rmRecord({required this.exerciseId, required this.record});

  final String exerciseId;

  /// The estimate, the set behind it and the previous best (0 for the first ever).
  final OneRmRecord record;
}

/// What finishing produces: the workout to store, the working weights to write and the records
/// for the summary.
class FinishedWorkout {
  const FinishedWorkout({required this.workout, required this.exWeights, required this.e1rmRecords});

  /// The record to save; `prs` holds the load records.
  final Workout workout;

  /// Working weights that went up, by exercise id — write each with `setExWeight`/`putExWeight`.
  final Map<String, ExWeight> exWeights;

  /// e1RM records of exercises that did not also set a load record.
  final List<E1rmRecord> e1rmRecords;

  /// Exercise ids that set a load record.
  List<String> get loadRecords => workout.prs;
}

bool _isReps(TrainingState state, ActiveEntry e) => targetModeOf(state.catalog, e.target, e.id) == ExerciseMode.reps;

num _maxDoneWeight(Iterable<SetRecord> sets) => sets.where((s) => s.done).fold<num>(0, (m, s) => max(m, s.w ?? 0));

/// Builds the finished record of [active] against [before] — the history **without** this
/// session — at [now] (engine.md §8.1).
///
/// * Entries without a done set are dropped; unchecked sets of kept entries stay. Each target is
///   stored with `id` and an explicit `mode` (engine-Q4).
/// * A load record is a reps-mode entry whose heaviest done set beats every done set and confirmed
///   `topW` in history (engine-Q5). An exercise logged twice counts once.
/// * An e1RM record is reported only for exercises without a load record.
/// * A reps-mode entry raises its working weight to `max(done sets, topW)` when that is higher.
FinishedWorkout finishWorkout(TrainingState before, ActiveWorkout active, {required DateTime now}) {
  final prs = <String>[];
  final e1rmRecords = <E1rmRecord>[];
  for (final e in active.entries) {
    if (_isReps(before, e)) {
      final top = _maxDoneWeight(e.sets);
      if (top > 0 && top > bestWeightFor(before, e.id) && !prs.contains(e.id)) prs.add(e.id);
    }
    final record = is1RMRecord(before.workouts, e.id, e.sets);
    if (record != null && !prs.contains(e.id) && !e1rmRecords.any((r) => r.exerciseId == e.id)) {
      e1rmRecords.add(E1rmRecord(exerciseId: e.id, record: record));
    }
  }

  final kept = [
    for (final e in active.entries)
      if (e.sets.any((s) => s.done))
        WorkoutEntry(
          id: e.id,
          sets: [for (final s in e.sets) s.copy()],
          topW: jsTruthy(e.topW) ? e.topW : null,
          target: _storedTarget(before, e),
        ),
  ];
  final workout = Workout(
    id: active.id,
    d: active.d,
    start: active.start,
    end: now.millisecondsSinceEpoch,
    routineId: active.routineId,
    name: active.name,
    bw: active.bw,
    entries: kept,
    prs: prs,
    vol: normNum(volumeOf(kept.expand((e) => e.sets))),
  );

  final exWeights = <String, ExWeight>{};
  for (final e in active.entries.where((e) => e.sets.any((s) => s.done))) {
    if (!_isReps(before, e)) continue;
    final top = max(_maxDoneWeight(e.sets), e.topW ?? 0);
    final current = exWeights[e.id] ?? before.exWeights[e.id];
    if (top > 0 && (current == null || top > current.w)) exWeights[e.id] = ExWeight(w: normNum(top), d: active.d);
  }
  return FinishedWorkout(workout: workout, exWeights: exWeights, e1rmRecords: e1rmRecords);
}

JsonMap _storedTarget(TrainingState state, ActiveEntry e) => {
  ...deepCopyMap(e.target),
  'id': e.id,
  'mode': targetModeOf(state.catalog, e.target, e.id),
};

/// The "Best" shown during a workout and in the top-weight sheet (engine.md §8.2): 0 for entries
/// not logged in reps mode (engine-Q5), else the higher of the load record and the working weight.
num previousBest(TrainingState state, ActiveEntry entry) {
  if (!_isReps(state, entry)) return 0;
  return max(bestWeightFor(state, entry.id), state.exWeights[entry.id]?.w ?? 0);
}

/// The top-weight sheet's starting value: `max(heaviest done set, previous best)`, else the
/// planned weight, else 0.
num topWeightSuggestion(TrainingState state, ActiveEntry entry) {
  final suggested = max(_maxDoneWeight(entry.sets), previousBest(state, entry));
  if (suggested > 0) return suggested;
  return numOr(asNum(entry.target['weight']), 0);
}

/// Confirming the top weight of an entry (specs/ui.md §5.9): the value is rounded to one decimal
/// and must be finite and ≥ 0. Returns the entry's `topW` and the working weight to store — never
/// lower than [current], always dated [today] — or null for an invalid value.
({num topW, ExWeight exWeight})? confirmTopWeight(num value, {ExWeight? current, required String today}) {
  if (!value.isFinite) return null;
  final n = round1(value);
  if (n < 0) return null;
  return (topW: n, exWeight: ExWeight(w: normNum(max(n, current?.w ?? 0)), d: today));
}
