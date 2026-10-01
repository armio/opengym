/// Port of `history.js` (specs/engine.md §2): logging modes, effort scales, set labels, the
/// "last time" lookups, the session prefill and simple aggregates.
library;

import 'dart:math';

import 'package:collection/collection.dart';

import '../data/dates.dart';
import '../data/models/active_workout.dart';
import '../data/models/json.dart';
import '../data/models/plan.dart';
import '../data/models/schedule.dart';
import '../data/models/settings.dart';
import '../data/models/workout.dart';
import 'calendar.dart';
import 'catalog.dart';
import 'format.dart';
import 'js.dart';
import 'training_state.dart';

/// How an exercise is logged: `reps` (`{w, r}` sets), `time` (`{sec, w}`) or `cardio`
/// (`{min, speed}`).
abstract final class ExerciseMode {
  static const reps = 'reps';
  static const time = 'time';
  static const cardio = 'cardio';
  static const all = [reps, time, cardio];

  static bool isValid(Object? mode) => mode == reps || mode == time || mode == cardio;
}

/// The mode for an explicit [mode] value and exercise [id]: a valid mode wins, else cardio by
/// body part, else reps.
String modeFor(ExerciseIndex catalog, {Object? mode, String? id}) {
  if (ExerciseMode.isValid(mode)) return mode! as String;
  return catalog.isCardio(id) ? ExerciseMode.cardio : ExerciseMode.reps;
}

/// `modeOf(cfg)`. An explicit valid mode always wins, even `reps` on a cardio exercise.
String modeOf(ExerciseIndex catalog, RoutineExercise? cfg) => modeFor(catalog, mode: cfg?.mode, id: cfg?.id);

/// The mode a stored or active entry was logged in: `modeOf({...target, id})`.
String targetModeOf(ExerciseIndex catalog, JsonMap? target, String id) =>
    modeFor(catalog, mode: target?['mode'], id: id);

/// [targetModeOf] of a finished workout entry.
String entryModeOf(ExerciseIndex catalog, WorkoutEntry entry) => targetModeOf(catalog, entry.target, entry.id);

/// `isTimed(cfg)`.
bool isTimed(ExerciseIndex catalog, RoutineExercise? cfg) => modeOf(catalog, cfg) == ExerciseMode.time;

// ---------------------------------------------------------------------------------------------
// Effort (RIR / RPE).

/// One effort scale: the set field it is stored in, its column label and the stepper range.
class EffortScale {
  const EffortScale({
    required this.field,
    required this.label,
    required this.step,
    required this.min,
    required this.max,
  });

  final String field;
  final String label;
  final num step;
  final num min;
  final num max;
}

/// `EFFORT`: RIR counts the reps left in the tank (0 = failure), RPE reads the same effort on a
/// 10-point scale (RPE 8 ≈ RIR 2). A set carries at most one, never converted.
const effortScales = {
  'rir': EffortScale(field: 'rir', label: 'RIR', step: 0.5, min: 0, max: 10),
  'rpe': EffortScale(field: 'rpe', label: 'RPE', step: 0.5, min: 6, max: 10),
};

/// `effortOf(S)`: `'none'`, `'rir'` or `'rpe'`. An explicit `'none'` beats the legacy `showRir`.
String effortOf(Settings? settings) => settings?.effortScale ?? 'none';

/// One tap of the effort stepper. `null` means "nothing logged" (delete the key): `+` on an empty
/// cell lands on the floor, `−` below the floor clears it; only the ceiling is enforced upwards.
num? stepEffort(String? kind, num? cur, int dir) {
  final scale = effortScales[kind];
  if (scale == null) return cur;
  if (cur == null) return dir < 0 ? null : scale.min;
  final next = jsRound((cur + dir * scale.step) * 100) / 100;
  if (dir < 0 && next < scale.min) return null;
  return normNum(dir > 0 ? min(scale.max, next) : max(scale.min, next));
}

/// A typed effort is capped but not floored, so typing "10" survives the "1" keystroke.
num? capEffort(String? kind, num? value) {
  final scale = effortScales[kind];
  return value == null || scale == null ? value : min(scale.max, value);
}

// ---------------------------------------------------------------------------------------------
// Labels and defaults.

/// One-line summary of a logged set: `"60×10 (RIR 2)"`, `"1:30 · 20"`, `"20 min @ 9 km/h"`.
/// [cfg] carries the mode when the caller has it; an id alone falls back to the body part.
String setLabel(ExerciseIndex catalog, String id, SetRecord s, [RoutineExercise? cfg]) {
  final mode = cfg != null ? modeOf(catalog, cfg) : modeFor(catalog, id: id);
  switch (mode) {
    case ExerciseMode.cardio:
      return '${fmtArg(numOr(s.min, 0))} min @ ${fmtNum(numOr(s.speed, 0))} km/h';
    case ExerciseMode.time:
      final w = s.w;
      return fmtSec(s.sec) + (w != null && w > 0 ? ' · ${fmtNum(w)}' : '');
    default:
      return '${fmtNum(numOr(s.w, 0))}×${fmtArg(numOr(s.r, 0))}${_effortTail(s)}';
  }
}

String _effortTail(SetRecord s) {
  final rir = s.rir, rpe = s.rpe;
  if (rir != null) return ' (RIR ${fmtNum(rir)})';
  if (rpe != null) return ' (RPE ${fmtNum(rpe)})';
  return '';
}

/// The config of a freshly added exercise.
RoutineExercise defaultConfig(ExerciseIndex catalog, String id, [String? mode]) {
  final m = (mode != null && mode.isNotEmpty) ? mode : modeFor(catalog, id: id);
  return switch (m) {
    ExerciseMode.cardio => RoutineExercise(id: id, sets: 1, min: 20, speed: 8),
    ExerciseMode.time => RoutineExercise(id: id, sets: 3, sec: 45, weight: 0, mode: ExerciseMode.time),
    _ => RoutineExercise(id: id, sets: 3, reps: 10, weight: 0, mode: ExerciseMode.reps),
  };
}

/// One-line summary of a planned exercise: `"3 × 10 · 60 kg"`, `"3 × 0:45"`, `"1 × 20 min @ 8 km/h"`.
String exLine(ExerciseIndex catalog, RoutineExercise cfg, String unit) {
  final n = numOr(cfg.sets, 1);
  final weight = cfg.weight;
  final load = jsTruthy(weight) ? ' · ${fmtNum(weight!)} $unit' : '';
  return switch (modeOf(catalog, cfg)) {
    ExerciseMode.cardio => '$n × ${fmtArg(numOr(cfg.min, 20))} min @ ${fmtNum(numOr(cfg.speed, 8))} km/h',
    ExerciseMode.time => '$n × ${fmtSec(numOr(cfg.sec, 45))}$load',
    _ => '$n × ${cfg.reps == null ? '' : fmtArg(cfg.reps)}$load',
  };
}

// ---------------------------------------------------------------------------------------------
// Supersets.

/// Drops every superset tag that no longer has an adjacent partner (sequential, in place).
void cleanupSg(List<RoutineExercise> ex) => Routine.cleanupSupersets(ex);

/// Groups consecutive indices sharing a superset tag: `[∅,a,a,b,a,∅] → [[0],[1,2],[3],[4],[5]]`.
/// Pass the `sg` of each routine exercise or active entry, in order.
List<List<int>> supersetUnits(Iterable<String?> tags) {
  final units = <List<int>>[];
  String? prev;
  var i = 0;
  for (final sg in tags) {
    if (i > 0 && jsTruthy(sg) && jsTruthy(prev) && sg == prev) {
      units.last.add(i);
    } else {
      units.add([i]);
    }
    prev = sg;
    i++;
  }
  return units;
}

/// The unit containing [index], or `[index]`.
List<int> unitOf(List<List<int>> units, int index) => units.firstWhereOrNull((u) => u.contains(index)) ?? [index];

// ---------------------------------------------------------------------------------------------
// History lookups.

/// "Last time" for an exercise: the date, done sets and stored target of its most recent session.
class LastEntry {
  const LastEntry({required this.d, required this.sets, this.target});

  final String d;

  /// Done sets only.
  final List<SetRecord> sets;

  /// The target the session was prescribed, or null for old and imported workouts.
  final JsonMap? target;
}

/// The most recent workout whose first entry of [exId] has a done set (workouts in `(d, start)`
/// order), or null.
LastEntry? lastEntryFor(List<Workout> workouts, String exId) {
  for (final w in workouts.reversed) {
    final entry = w.entries.firstWhereOrNull((e) => e.id == exId);
    if (entry != null && entry.sets.any((s) => s.done)) {
      return LastEntry(d: w.d, sets: [...entry.sets.where((s) => s.done)], target: entry.target);
    }
  }
  return null;
}

/// The heaviest load ever handled for [exId]: done sets' `w` and confirmed `topW`, over entries
/// logged in reps mode only (engine-Q5). 0 when never loaded.
num bestWeightFor(TrainingState state, String exId) {
  num best = 0;
  for (final w in state.workouts) {
    for (final e in w.entries) {
      if (e.id != exId || entryModeOf(state.catalog, e) != ExerciseMode.reps) continue;
      for (final s in e.sets) {
        final weight = s.w;
        if (s.done && weight != null && weight > best) best = weight;
      }
      final topW = e.topW;
      if (topW != null && topW > best) best = topW;
    }
  }
  return best;
}

/// The routine id [iso] trains: a per-date override (`'rest'` or an existing routine), else the
/// weekly plan — which may still name a deleted routine (see [effectiveRoutine]).
String? effectiveRoutineId(PlanDoc plan, ScheduleDoc schedule, String iso) {
  final override = schedule.dayPlan[iso];
  if (override == 'rest') return null;
  if (override != null && override.isNotEmpty && plan.routines.any((r) => r.id == override)) return override;
  final id = plan.week['${weekdayOf(iso)}'];
  return id == null || id.isEmpty ? null : id;
}

/// The routine [iso] trains, or null (rest, or a stale id).
Routine? effectiveRoutine(PlanDoc plan, ScheduleDoc schedule, String iso) =>
    plan.routineById(effectiveRoutineId(plan, schedule, iso));

// ---------------------------------------------------------------------------------------------
// Session prefill.

/// Fresh sets for a new session, before the prescription is applied (engine.md §2.14): last
/// time's done set at the same position (its final one when the plan grew), else the plan. For
/// reps the confirmed working weight beats last session's weights. When the plan's rep or hold
/// target changed since the last stored target, reps / seconds come from the plan (critic-G3).
List<SetRecord> buildSets(TrainingState state, RoutineExercise cfg) {
  final last = lastEntryFor(state.workouts, cfg.id);
  final n = max(1, numOr(cfg.sets, 1)).toInt();
  SetRecord? prevAt(int i) => last == null ? null : (i < last.sets.length ? last.sets[i] : last.sets.last);

  bool retarget(String key, num? planned) {
    final stored = last?.target?[key];
    return stored is num && stored > 0 && stored != planned;
  }

  switch (modeOf(state.catalog, cfg)) {
    case ExerciseMode.cardio:
      return [
        for (var i = 0; i < n; i++)
          if (prevAt(i) case final prev?)
            SetRecord(min: prev.min, speed: prev.speed)
          else
            SetRecord(min: numOr(cfg.min, 20), speed: numOr(cfg.speed, 8)),
      ];
    case ExerciseMode.time:
      final newTarget = retarget('sec', cfg.sec);
      return [
        for (var i = 0; i < n; i++)
          if (prevAt(i) case final prev? when (prev.sec ?? 0) > 0)
            SetRecord(sec: newTarget ? numOr(cfg.sec, 45) : prev.sec, w: numOr(prev.w, 0))
          else
            SetRecord(sec: numOr(cfg.sec, 45), w: numOr(cfg.weight, 0)),
      ];
    default:
      final working = state.exWeights[cfg.id]?.w;
      final newTarget = retarget('reps', cfg.reps);
      return [
        for (var i = 0; i < n; i++)
          if (prevAt(i) case final prev? when (prev.r ?? 0) > 0)
            SetRecord(w: working != null && working > 0 ? working : prev.w, r: newTarget ? cfg.reps : prev.r)
          else
            SetRecord(w: working != null && working > 0 ? working : cfg.weight, r: cfg.reps),
      ];
  }
}

// ---------------------------------------------------------------------------------------------
// Aggregates.

/// Σ `w × r` over done sets; timed and cardio sets add nothing.
num volumeOf(Iterable<SetRecord> sets) {
  num volume = 0;
  for (final s in sets) {
    if (s.done) volume += numOr(s.w, 0) * numOr(s.r, 0);
  }
  return volume;
}

/// `workoutVolume(w)`.
num workoutVolume(Workout workout) => volumeOf(workout.entries.expand((e) => e.sets));

/// Done sets across a workout's entries.
int setsDone(Workout workout) => workout.entries.expand((e) => e.sets).where((s) => s.done).length;

/// Done sets of the workout in progress (0 without one).
int setsDoneActive(ActiveWorkout? active) =>
    active == null ? 0 : active.entries.expand((e) => e.sets).where((s) => s.done).length;

/// All sets of the workout in progress, checked or not.
int setsTotalActive(ActiveWorkout? active) => active == null ? 0 : active.entries.fold(0, (n, e) => n + e.sets.length);

/// Consecutive ISO weeks with at least one workout, counting back from the week of [now]. An
/// empty current week does not break the streak (yet). Capped at 520 weeks.
int streakWeeks(Iterable<Workout> workouts, {required DateTime now, LocalCalendar calendar = deviceCalendar}) {
  final weeks = {
    for (final w in workouts)
      if (isIsoDate(w.d)) weekKey(w.d),
  };
  if (weeks.isEmpty) return 0;
  final today = calendar.today(now);
  var streak = 0;
  for (var i = 0; i < 520; i++) {
    if (weeks.contains(weekKey(addDays(today, -7 * i)))) {
      streak++;
    } else if (i > 0) {
      break;
    }
  }
  return streak;
}

/// Workouts in the order everything order-dependent reads them: `(d, start)` ascending, stable
/// (engine-Q6). A date-only workout already sits at local noon of its date (engine-Q7, applied
/// when the model is read). Returns a new list.
List<Workout> sortWorkouts(Iterable<Workout> workouts) {
  final sorted = [...workouts];
  mergeSort(sorted, compare: Workout.compare);
  return sorted;
}
