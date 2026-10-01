/// The guided workout's edits to the active session, as pure functions on an [ActiveWorkout]
/// (call them inside `AppState.updateActive`): checking a set off (specs/ui.md §5.6), adding and
/// removing sets (§5.5), editing a set field and moving between superset units (§5.4).
library;

import '../../../data/models/models.dart';
import '../../../engine/engine.dart';

/// What the rest timer should do after a set was checked.
enum RestChange { none, start, stop }

/// What checking or unchecking a set leads to.
class SetToggle {
  const SetToggle({
    required this.mode,
    this.checked = false,
    this.rest = RestChange.none,
    this.askTopWeight = false,
    this.workoutDone = false,
    this.exerciseDone = false,
  });

  /// The entry's logging mode.
  final String mode;

  /// The set is now done (false: it was unchecked — nothing else happens).
  final bool checked;
  final RestChange rest;

  /// Show the top-weight sheet: a reps entry just had all its sets done for the first time.
  final bool askTopWeight;

  /// The last unit was just completed: "¡Ese era todo el entrenamiento!".
  final bool workoutDone;

  /// Every set of the entry is done.
  final bool exerciseDone;
}

/// The superset units of [active]: consecutive entries sharing a tag (`supersetUnits`).
List<List<int>> unitsOf(ActiveWorkout active) => supersetUnits([for (final e in active.entries) e.sg]);

/// The entry on screen: `cur` clamped to the entries.
int currentIndex(ActiveWorkout active) =>
    active.entries.isEmpty ? 0 : active.cur.clamp(0, active.entries.length - 1).toInt();

/// Whether every set of every entry in [unit] is done.
bool unitDone(ActiveWorkout active, List<int> unit) => unit.every((i) => active.entries[i].sets.every((s) => s.done));

/// `toggle(idx, i)` — flips set [setIndex] of entry [entryIndex] and decides what follows:
///
/// * a rest starts after a set of the **last** member of a superset unit while the unit is not
///   done; a completed unit stops the rest (nothing to rest for);
/// * completing the last unit completes the workout;
/// * a reps entry whose sets are all done asks for its top weight once (`asked` is stored);
/// * unchecking does nothing else (a running rest keeps running).
///
/// The unit is the one containing the entry — the unit on screen for a tap, and the right one
/// for a hold that ends after the owner moved on (critic-G1: no stale unit).
SetToggle toggleSet(ActiveWorkout active, int entryIndex, int setIndex, ExerciseIndex catalog) {
  final entry = active.entries[entryIndex];
  final mode = targetModeOf(catalog, entry.target, entry.id);
  final set = entry.sets[setIndex];
  set.done = !set.done;
  if (!set.done) return SetToggle(mode: mode);

  final units = unitsOf(active);
  final unitIndex = units.indexWhere((u) => u.contains(entryIndex));
  final unit = units[unitIndex];
  final done = unitDone(active, unit);
  final isLastInUnit = entryIndex == unit.last;
  final rest = isLastInUnit && !done
      ? RestChange.start
      : done
      ? RestChange.stop
      : RestChange.none;

  final exerciseDone = entry.sets.every((s) => s.done);
  var askTop = false;
  if (exerciseDone && mode == ExerciseMode.reps && !entry.asked) {
    entry.asked = true;
    askTop = true;
  }
  return SetToggle(
    mode: mode,
    checked: true,
    rest: rest,
    askTopWeight: askTop,
    workoutDone: done && unitIndex >= units.length - 1,
    exerciseDone: exerciseDone,
  );
}

/// "Añadir serie": a copy of the last set's values, unchecked and without effort (or the
/// target's values for an entry without sets).
void addSet(ActiveEntry entry, ExerciseIndex catalog) {
  final last = entry.sets.isEmpty ? null : entry.sets.last;
  final t = entry.target;
  num? target(String key) => t[key] is num ? t[key] as num : null;
  num targetOr(String key, num fallback) => numOr(target(key), fallback);
  entry.sets.add(switch (targetModeOf(catalog, t, entry.id)) {
    ExerciseMode.cardio => SetRecord(
      min: last != null ? last.min : targetOr('min', 20),
      speed: last != null ? last.speed : targetOr('speed', 8),
    ),
    ExerciseMode.time => SetRecord(
      sec: last != null ? last.sec : targetOr('sec', 45),
      w: last != null ? (last.w ?? 0) : targetOr('weight', 0),
    ),
    _ => SetRecord(w: last != null ? last.w : 0, r: last != null ? last.r : target('reps')),
  });
}

/// "Quitar serie": drops the last set, never the only one.
void removeSet(ActiveEntry entry) {
  if (entry.sets.length > 1) entry.sets.removeLast();
}

/// The set fields the steppers edit.
abstract final class SetField {
  static const w = 'w';
  static const r = 'r';
  static const sec = 'sec';
  static const min = 'min';
  static const speed = 'speed';
  static const rir = 'rir';
  static const rpe = 'rpe';
}

/// Writes [value] into [field] of [set]; null removes the key (an unlogged effort is not 0).
void setSetField(SetRecord set, String field, num? value) {
  switch (field) {
    case SetField.w:
      set.w = value;
    case SetField.r:
      set.r = value;
    case SetField.sec:
      set.sec = value;
    case SetField.min:
      set.min = value;
    case SetField.speed:
      set.speed = value;
    case SetField.rir:
      set.rir = value;
    case SetField.rpe:
      set.rpe = value;
    default:
      throw ArgumentError.value(field, 'field');
  }
}

/// Reads [field] of [set].
num? setFieldOf(SetRecord set, String field) => switch (field) {
  SetField.w => set.w,
  SetField.r => set.r,
  SetField.sec => set.sec,
  SetField.min => set.min,
  SetField.speed => set.speed,
  SetField.rir => set.rir,
  SetField.rpe => set.rpe,
  _ => throw ArgumentError.value(field, 'field'),
};

/// "Anterior" / "Siguiente": `cur` moves to the first entry of the unit [delta] away from the
/// current one. Returns false at either end.
bool moveUnit(ActiveWorkout active, int delta) {
  if (active.entries.isEmpty) return false;
  final units = unitsOf(active);
  final current = units.indexWhere((u) => u.contains(currentIndex(active)));
  final next = current + delta;
  if (current < 0 || next < 0 || next >= units.length) return false;
  active.cur = units[next].first;
  return true;
}
