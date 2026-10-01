import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../widgets/formatting.dart';
import 'services/rest_alerts.dart';
import 'services/screen_wake_lock.dart';
import 'services/workout_feedback.dart';
import 'services/workout_timers.dart';
import 'set_editing.dart';

/// Something the workout screen should show in response to a set being checked (also when a
/// hold checks it off by itself).
sealed class WorkoutPrompt {
  const WorkoutPrompt();
}

/// Open the top-weight sheet for entry [entry] (specs/ui.md §5.9).
class AskTopWeight extends WorkoutPrompt {
  const AskTopWeight(this.entry);

  final int entry;
}

/// "¡Ese era todo el entrenamiento!" (specs/ui.md §5.10).
class WorkoutCompleted extends WorkoutPrompt {
  const WorkoutCompleted();
}

/// A toast.
class WorkoutToast extends WorkoutPrompt {
  const WorkoutToast(this.message);

  final String message;
}

/// How confirming a top weight ended.
enum TopWeightOutcome {
  /// Not a valid weight; nothing saved.
  invalid,

  /// Saved; the toast "Registrado — …" was posted.
  tracked,

  /// Saved and moved on to the next unit.
  advanced,

  /// Saved and the workout is complete: show the complete dialog.
  completed,
}

/// What the finish summary shows.
class FinishSummary {
  const FinishSummary({required this.workout, required this.e1rmRecords, required this.muscleLevels});

  /// The stored workout (its `prs` are the load records).
  final Workout workout;
  final List<E1rmRecord> e1rmRecords;

  /// `levelsOf(loadOfActive(…))` of the session's done sets.
  final Map<String, int> muscleLevels;
}

/// The guided workout's logic between the screens and [AppState] (one per app, provided at the
/// root): starting, the set check-off algorithm with its rest timer and prompts, holds, the
/// top-weight confirmation, adding exercises, discarding and finishing. It also keeps the
/// screen awake while a workout is active and `settings.keepAwake` is on (specs/ui.md §1.8).
///
/// Every change to the session goes through `AppState.updateActive` (active.json); working
/// weights and finished workouts through the synced mutations.
class WorkoutController {
  WorkoutController({
    required this.app,
    RestAlerts alerts = const NoRestAlerts(),
    WorkoutFeedback? feedback,
    this.wakeLock = const PlatformWakeLock(),
    bool Function()? isForeground,
  }) : feedback = feedback ?? WorkoutFeedback(soundOn: () => app.settings.sound) {
    timers = WorkoutTimers(clock: app.clock, alerts: alerts, feedback: this.feedback, isForeground: isForeground)
      ..onRestOver = (() => _prompt(const WorkoutToast('¡Descanso terminado — siguiente serie!')))
      ..onHoldDone = _logHold;
    _activeId = app.active?.id;
    app.addListener(_onAppChanged);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _syncWakeLock();
  }

  final AppState app;
  final WorkoutFeedback feedback;
  final ScreenWakeLock wakeLock;
  late final WorkoutTimers timers;
  late final AppLifecycleListener _lifecycle;
  final _prompts = StreamController<WorkoutPrompt>.broadcast();
  String? _activeId;
  bool _wakeWanted = false;

  /// Prompts for the workout screen.
  Stream<WorkoutPrompt> get prompts => _prompts.stream;

  ActiveWorkout? get active => app.active;

  ExerciseIndex get _catalog => app.exerciseIndex;

  /// The routine the session was started from, if it still exists (for inherited policies).
  Routine? get sessionRoutine => app.plan.routineById(app.active?.routineId);

  // ---------------------------------------------------------------------------------------
  // Lifecycle.

  /// Starts [routine] (null = freestyle) with the check-in weight [bodyWeight] (specs/ui.md
  /// §5.3): every entry prefilled with its prescription. Timers of a previous session stop.
  Future<void> begin(Routine? routine, {num? bodyWeight}) async {
    timers
      ..stopRest()
      ..cancelHold();
    await app.startActive(startSession(app.trainingState, routine, bw: bodyWeight, now: app.clock.now()));
  }

  /// "Descartar": the session is thrown away.
  Future<void> discard() async {
    timers
      ..stopRest()
      ..cancelHold();
    await app.discardActive();
  }

  /// Finishes the session (specs/ui.md §5.11): load and e1RM records against the history
  /// before it, the stored record with each target's id and mode, raised working weights.
  /// Returns null without an active workout.
  Future<FinishSummary?> finish() async {
    final active = app.active;
    if (active == null) return null;
    timers
      ..stopRest()
      ..cancelHold();
    final levels = levelsOf(loadOfActive(_catalog, active));
    final result = finishWorkout(app.trainingState, active, now: app.clock.now());
    await app.finishActive((d) {
      d.putWorkout(result.workout);
      result.exWeights.forEach(d.putExWeight);
    });
    feedback.workoutFinished();
    return FinishSummary(workout: result.workout, e1rmRecords: result.e1rmRecords, muscleLevels: levels);
  }

  // ---------------------------------------------------------------------------------------
  // Sets.

  /// Checks or unchecks a set and runs what follows: beep, rest, prompts (§5.6).
  void toggle(int entry, int set) {
    final active = app.active;
    if (active == null || !_exists(active, entry, set)) return;
    late SetToggle t;
    app.updateActive((a) => t = toggleSet(a, entry, set, _catalog));
    if (!t.checked) return;
    feedback.setChecked();
    switch (t.rest) {
      case RestChange.start:
        timers.startRest(app.settings.restSec);
      case RestChange.stop:
        timers.stopRest();
      case RestChange.none:
        break;
    }
    if (t.askTopWeight) {
      _prompt(AskTopWeight(entry));
    } else if (t.workoutDone) {
      _prompt(const WorkoutCompleted());
    } else if (t.exerciseDone && t.mode == ExerciseMode.cardio) {
      _prompt(const WorkoutToast('Cardio registrado'));
    } else if (t.exerciseDone && t.mode == ExerciseMode.time) {
      _prompt(const WorkoutToast('Isométrico registrado'));
    }
  }

  /// A stepper or a typed value; null removes the field.
  void setField(int entry, int set, String field, num? value) {
    final active = app.active;
    if (active == null || !_exists(active, entry, set)) return;
    app.updateActive((a) => setSetField(a.entries[entry].sets[set], field, value));
  }

  void addSetTo(int entry) {
    if (!_hasEntry(entry)) return;
    app.updateActive((a) => addSet(a.entries[entry], _catalog));
  }

  void removeSetFrom(int entry) {
    if (!_hasEntry(entry)) return;
    app.updateActive((a) => removeSet(a.entries[entry]));
  }

  /// "Anterior" (−1) / "Siguiente" (+1).
  void moveBy(int delta) {
    if (app.active == null) return;
    app.updateActive((a) => moveUnit(a, delta));
  }

  /// ▶ on a timed set: counts the hold down, then logs the seconds held and checks the set off.
  void startHold(int entry, int set) {
    final active = app.active;
    if (active == null || !_exists(active, entry, set)) return;
    final e = active.entries[entry];
    timers.startHold(
      numOr(e.sets[set].sec, 45),
      label: capitalizeWords(app.catalog.exOr(e.id).name),
      target: HoldTarget(activeId: active.id, entry: entry, set: set),
    );
  }

  void _logHold(HoldTarget target, int elapsed) {
    final active = app.active;
    if (active == null || active.id != target.activeId || !_exists(active, target.entry, target.set)) return;
    app.updateActive((a) => a.entries[target.entry].sets[target.set].sec = elapsed);
    if (!app.active!.entries[target.entry].sets[target.set].done) toggle(target.entry, target.set);
  }

  // ---------------------------------------------------------------------------------------
  // Top weight.

  /// "Guardar" in the top-weight sheet: stores `topW` on the entry and raises the working
  /// weight (never lowers it). With [advance] and the unit done, moves to the next unit or
  /// reports the workout complete.
  TopWeightOutcome saveTopWeight(int entry, num value, {required bool advance}) {
    final active = app.active;
    if (active == null || !_hasEntry(entry)) return TopWeightOutcome.invalid;
    final id = active.entries[entry].id;
    final result = confirmTopWeight(value, current: app.exWeights[id], today: app.clock.todayIso());
    if (result == null) return TopWeightOutcome.invalid;
    app.updateActive((a) => a.entries[entry].topW = result.topW);
    // Stored even when 0 (a bodyweight exercise), as the original does (data-model §1.8); the
    // Worker accepts working weights >= 0 and buildSets ignores a 0 when seeding.
    app.setExWeight(id, result.exWeight.w, date: result.exWeight.d);

    final now = app.active!;
    final units = unitsOf(now);
    final unitIndex = units.indexWhere((u) => u.contains(entry));
    if (advance && unitDone(now, units[unitIndex])) {
      if (unitIndex >= units.length - 1) return TopWeightOutcome.completed;
      app.updateActive((a) => a.cur = units[unitIndex + 1].first);
      return TopWeightOutcome.advanced;
    }
    final w = app.exWeights[id]?.w ?? result.exWeight.w;
    _prompt(WorkoutToast('Registrado — la próxima vez empiezas en ${fmtVol(w, app.settings.unit)}'));
    return TopWeightOutcome.tracked;
  }

  // ---------------------------------------------------------------------------------------
  // Adding an exercise (§5.12).

  /// Appends [config] as a new entry (prescribed like a routine exercise, never in a superset)
  /// and jumps to it.
  void addExercise(RoutineExercise config) {
    if (app.active == null) return;
    final entry = buildActiveEntry(app.trainingState, config.copy()..sg = null, sessionRoutine);
    app.updateActive((a) {
      a.entries.add(entry);
      a.cur = a.entries.length - 1;
    });
  }

  // ---------------------------------------------------------------------------------------

  bool _hasEntry(int entry) {
    final a = app.active;
    return a != null && entry >= 0 && entry < a.entries.length;
  }

  static bool _exists(ActiveWorkout a, int entry, int set) =>
      entry >= 0 && entry < a.entries.length && set >= 0 && set < a.entries[entry].sets.length;

  void _prompt(WorkoutPrompt prompt) {
    if (!_prompts.isClosed) _prompts.add(prompt);
  }

  void _onAppChanged() {
    final id = app.active?.id;
    if (id != _activeId) {
      // Finished, discarded, replaced or wiped: no timer may outlive its workout (critic-G1).
      _activeId = id;
      timers
        ..stopRest()
        ..cancelHold();
    }
    _syncWakeLock();
  }

  void _onResume() {
    timers.tick();
    if (_wakeWanted) unawaited(wakeLock.acquire());
  }

  void _syncWakeLock() {
    final wanted = app.active != null && app.settings.keepAwake;
    if (wanted == _wakeWanted) return;
    _wakeWanted = wanted;
    unawaited(wanted ? wakeLock.acquire() : wakeLock.release());
  }

  void dispose() {
    app.removeListener(_onAppChanged);
    _lifecycle.dispose();
    timers.dispose();
    _prompts.close();
    if (_wakeWanted) unawaited(wakeLock.release());
  }
}
