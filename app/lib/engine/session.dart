/// Building a session (specs/engine.md §2.14 pipeline, specs/ui.md §5.3 and §5.12): each routine
/// exercise gets its prescription and prefilled sets.
library;

import '../data/models/active_workout.dart';
import '../data/models/json.dart';
import '../data/models/plan.dart';
import 'calendar.dart';
import 'catalog.dart';
import 'format.dart';
import 'history.dart';
import 'progression.dart';
import 'training_state.dart';

/// Name of a session started without a routine.
const freestyleName = 'Libre';

/// The target stored with an entry: the plan config with its `id` and an explicit `mode`
/// (engine-Q4), so the session can always be read back the way it was logged.
JsonMap sessionTarget(ExerciseIndex catalog, RoutineExercise cfg) => {
  ...cfg.toJson(),
  'id': cfg.id,
  'mode': modeOf(catalog, cfg),
};

/// One entry of a new session: `nextPrescription`, then `buildSets` with the prescription
/// applied. Use it for routine exercises and for exercises added mid-session (pass a config
/// without `sg`: added entries are never part of a superset).
ActiveEntry buildActiveEntry(TrainingState state, RoutineExercise cfg, [Routine? routine]) {
  final plan = nextPrescription(state, cfg, routine);
  return ActiveEntry(
    id: cfg.id,
    sg: cfg.sg,
    target: sessionTarget(state.catalog, cfg),
    plan: plan,
    sets: applyPrescription(buildSets(state, cfg), plan),
  );
}

/// A new session of [routine] (or a freestyle one), started at [now] with the check-in body
/// weight [bw] (0 or null when skipped).
ActiveWorkout startSession(
  TrainingState state,
  Routine? routine, {
  num? bw,
  required DateTime now,
  LocalCalendar calendar = deviceCalendar,
}) => ActiveWorkout(
  id: uid(now),
  d: calendar.today(now),
  start: now.millisecondsSinceEpoch,
  routineId: routine?.id,
  name: routine?.name ?? freestyleName,
  bw: bw == null || bw == 0 ? null : bw,
  entries: [for (final cfg in routine?.ex ?? const <RoutineExercise>[]) buildActiveEntry(state, cfg, routine)],
);
