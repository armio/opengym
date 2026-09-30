/// Port of `progression.js` (specs/engine.md §4): automatic progression — linear, Greyskull,
/// double progression and timed holds — with engine-Q1 (double-progression stalls), engine-Q2
/// (timed deload step) and critic-G3 (a changed plan target starts a new baseline).
///
/// Nothing is stored: every prescription is derived from history when a session is built.
library;

import 'dart:math';

import 'package:collection/collection.dart';

import '../data/models/active_workout.dart';
import '../data/models/json.dart';
import '../data/models/plan.dart';
import '../data/models/workout.dart';
import 'catalog.dart';
import 'history.dart';
import 'js.dart';
import 'training_state.dart';
import 'why.dart';

/// Every progression policy.
const policies = ['off', 'linear', 'greyskull', 'double', 'time'];

/// The policies each logging mode accepts.
const policiesFor = {
  ExerciseMode.reps: ['off', 'linear', 'greyskull', 'double'],
  ExerciseMode.time: ['off', 'time'],
  ExerciseMode.cardio: ['off'],
};

/// Consecutive missed sessions before a deload.
const deloadAfter = {'linear': 3, 'greyskull': 1, 'double': 3, 'time': 3};

/// The default step of a timed hold, in seconds.
const defaultSecIncrement = 5;

const _deloadFactor = 0.9;

/// Body parts that take the bigger jump (`hips` and `glutes` never occur; kept for parity).
const _heavyBodyParts = {'upper legs', 'lower legs', 'back', 'hips', 'glutes'};

/// Spanish name of each policy (`POLICY_NAME`).
const policyNames = {
  'off': 'Sin progresión automática',
  'linear': 'Progresión lineal',
  'greyskull': 'Greyskull LP',
  'double': 'Progresión doble',
  'time': 'Añadir tiempo',
};

/// Spanish one-line description of each policy (`POLICY_DESC`).
const policyDescriptions = {
  'off': 'Los objetivos se quedan como los pongas.',
  'linear': 'Si completas todas las repeticiones de todas las series, sube el peso. Los fallos repetidos provocan una descarga.',
  'greyskull': 'Dos series normales más una final al fallo. Si superas el objetivo en esa serie, sube el peso; el doble si doblas las repeticiones. Un fallo reduce un 10 %.',
  'double': 'Sube por un rango de repeticiones con el mismo peso. Alcanza el tope del rango en todas las series y el peso sube, con las repeticiones de vuelta al mínimo.',
  'time': 'Aguanta todas las series el tiempo completo y el objetivo sube.',
};

// ---------------------------------------------------------------------------------------------
// Sessions.

/// One logged entry reduced to what the policies judge (`readSession`).
sealed class Session {
  const Session({required this.mode, required this.goal, required this.weight, required this.ok, this.d});

  final String mode;

  /// Target reps (or seconds) the session was judged against; 0 when unknown.
  final num goal;

  /// Heaviest done set; 0 means bodyweight.
  final num weight;

  /// Every prescribed set checked off at or above [goal].
  final bool ok;

  /// The workout's date, for sessions read from history.
  final String? d;

  Session dated(String d);

  JsonMap toJson();
}

/// A reps (or cardio, read the reps way and never judged) session.
final class RepsSession extends Session {
  const RepsSession({
    super.mode = ExerciseMode.reps,
    required super.goal,
    required this.reps,
    required super.weight,
    required this.low,
    required this.amrap,
    required super.ok,
    super.d,
  });

  /// Reps per set; an unchecked set counts 0.
  final List<num> reps;

  /// The worst set.
  final num low;

  /// The final set — Greyskull's AMRAP.
  final num amrap;

  @override
  RepsSession dated(String d) =>
      RepsSession(mode: mode, goal: goal, reps: reps, weight: weight, low: low, amrap: amrap, ok: ok, d: d);

  @override
  JsonMap toJson() => {
    'd': ?d,
    'mode': mode,
    'goal': goal,
    'reps': reps,
    'weight': weight,
    'low': low,
    'amrap': amrap,
    'ok': ok,
  };
}

/// A timed session.
final class TimeSession extends Session {
  const TimeSession({
    required super.goal,
    required this.held,
    required super.weight,
    required this.best,
    required super.ok,
    super.d,
  }) : super(mode: ExerciseMode.time);

  /// Seconds held per set; an unchecked set counts 0.
  final List<num> held;
  final num best;

  @override
  TimeSession dated(String d) => TimeSession(goal: goal, held: held, weight: weight, best: best, ok: ok, d: d);

  @override
  JsonMap toJson() => {'d': ?d, 'mode': mode, 'goal': goal, 'held': held, 'weight': weight, 'best': best, 'ok': ok};
}

num _maxOf(Iterable<num> values) => values.fold<num>(0, max);

/// A number of a stored target. Targets are open JSON from any writer; a numeric string compares
/// as its number, as it did in JavaScript.
num? _targetNum(Object? value) => switch (value) {
  num n when n.isFinite => n,
  String s => num.tryParse(s.trim()),
  _ => null,
};

/// Reduces one logged entry to a [Session]. An entry without its own target (older workouts,
/// imports) is judged against [fallback], the exercise's current plan config. A hit needs every
/// prescribed set checked off at or above the goal; a missing goal is always a miss.
Session readSession(ExerciseIndex catalog, WorkoutEntry? entry, [RoutineExercise? fallback]) {
  final stored = entry?.target;
  final targetSets = stored != null ? _targetNum(stored['sets']) : fallback?.sets;
  final targetReps = stored != null ? _targetNum(stored['reps']) : fallback?.reps;
  final targetSec = stored != null ? _targetNum(stored['sec']) : fallback?.sec;
  final mode = modeFor(catalog, mode: stored != null ? stored['mode'] : fallback?.mode, id: entry?.id);
  final sets = entry?.sets ?? const <SetRecord>[];
  final enough = sets.length >= numOr(targetSets, sets.length);
  final weight = _maxOf(sets.where((s) => s.done).map((s) => numOr(s.w, 0)));

  if (mode == ExerciseMode.time) {
    final goal = numOr(targetSec, 0);
    final held = [for (final s in sets) s.done ? numOr(s.sec, 0) : 0];
    return TimeSession(
      goal: goal,
      held: held,
      weight: weight,
      best: _maxOf(held),
      ok: goal > 0 && enough && held.isNotEmpty && held.every((h) => h >= goal),
    );
  }
  final goal = numOr(targetReps, 0);
  final reps = [for (final s in sets) s.done ? numOr(s.r, 0) : 0];
  return RepsSession(
    mode: mode,
    goal: goal,
    reps: reps,
    weight: weight,
    low: reps.isEmpty ? 0 : reps.reduce(min),
    amrap: reps.isEmpty ? 0 : reps.last,
    ok: goal > 0 && enough && reps.isNotEmpty && reps.every((r) => r >= goal),
  );
}

/// Every session of [exId] with a done set, oldest first: per workout its first entry of the
/// exercise (workouts in `(d, start)` order).
List<Session> sessionsFor(TrainingState state, String exId, [RoutineExercise? fallback]) => [
  for (final w in state.workouts)
    if (w.entries.firstWhereOrNull((e) => e.id == exId) case final entry? when entry.sets.any((s) => s.done))
      readSession(state.catalog, entry, fallback).dated(w.d),
];

/// Consecutive misses counting back from the most recent session.
int stallCount(List<Session> sessions) {
  var n = 0;
  for (final s in sessions.reversed) {
    if (s.ok) break;
    n++;
  }
  return n;
}

/// engine-Q1: double progression climbs a rep range at one weight, so a miss only counts as a
/// stall when its worst set did not improve on the session before at the same weight.
int doubleStallCount(List<RepsSession> sessions) {
  var n = 0;
  for (var i = sessions.length - 1; i >= 0; i--) {
    final s = sessions[i];
    final prev = i > 0 ? sessions[i - 1] : null;
    final stalled = !s.ok && (prev == null || prev.weight != s.weight || s.low <= prev.low);
    if (!stalled) break;
    n++;
  }
  return n;
}

/// Consecutive missed sessions as [policy] counts them: double progression only counts misses
/// that did not improve; cardio is never judged, so it never stalls.
int stallsFor(String policy, String mode, List<Session> sessions) {
  if (mode == ExerciseMode.cardio) return 0;
  if (policy == 'double' && mode == ExerciseMode.reps) {
    return doubleStallCount(sessions.whereType<RepsSession>().toList());
  }
  return stallCount(sessions);
}

// ---------------------------------------------------------------------------------------------
// Policy and increment.

/// The policy in force: the exercise's own, else the routine's, else the mode's default
/// (`reps → linear`, others `off`). A policy the mode does not accept is `off` — the lookup
/// does not fall back a level.
String policyFor(ExerciseIndex catalog, RoutineExercise? cfg, Routine? routine, [String? mode]) {
  final m = (mode != null && mode.isNotEmpty) ? mode : modeOf(catalog, cfg);
  final allowed = policiesFor[m] ?? const ['off'];
  final pick = jsOr(cfg?.prog, jsOr(routine?.prog, m == ExerciseMode.reps ? 'linear' : 'off'));
  return allowed.contains(pick) ? pick! as String : 'off';
}

/// The default load step: 5 kg / 10 lb for legs and back, 2.5 kg / 5 lb for everything else.
num defaultIncrement(ExerciseIndex catalog, String exId, String unit) {
  final heavy = _heavyBodyParts.contains(catalog.lookup(exId)?.bodyPart);
  if (unit == 'lb') return heavy ? 10 : 5;
  return heavy ? 5 : 2.5;
}

/// The step a config progresses by: its own `inc`, else 5 s for timed work, else [defaultIncrement].
num incrementFor(ExerciseIndex catalog, RoutineExercise cfg, String unit) {
  final inc = cfg.inc;
  if (inc != null && inc > 0) return inc;
  return modeOf(catalog, cfg) == ExerciseMode.time ? defaultSecIncrement : defaultIncrement(catalog, cfg.id, unit);
}

/// The nearest loadable multiple of [step], to one decimal.
num _snap(num v, num step) => step > 0 ? round1(jsRound(v / step) * step) : round1(v);

/// About 10 % lighter, on the grid, strictly lighter than [cur], never below one step.
num _deloadTo(num cur, num step) {
  var next = _snap(cur * _deloadFactor, step);
  if (next >= cur) next = _snap(cur - step, step);
  return normNum(max(step, next));
}

// ---------------------------------------------------------------------------------------------
// The prescription.

/// The stored target of the last session in [mode] (critic-G3 reads it field by field).
JsonMap? _lastTargetOf(TrainingState state, RoutineExercise cfg, String mode) {
  for (final w in state.workouts.reversed) {
    final entry = w.entries.firstWhereOrNull((e) => e.id == cfg.id);
    if (entry == null || !entry.sets.any((s) => s.done)) continue;
    final sessionMode = modeFor(
      state.catalog,
      mode: entry.target != null ? entry.target!['mode'] : cfg.mode,
      id: entry.id,
    );
    if (sessionMode == mode) return entry.target;
  }
  return null;
}

/// critic-G3: the plan's rep (or hold) target differs from the one stored with the last session.
/// A missing target, or a target without the field, never triggers it.
bool _planTargetChanged(TrainingState state, RoutineExercise cfg, String mode) {
  final isTime = mode == ExerciseMode.time;
  final stored = _lastTargetOf(state, cfg, mode)?[isTime ? 'sec' : 'reps'];
  return stored is num && stored > 0 && stored != (isTime ? cfg.sec : cfg.reps);
}

/// The next prescription for one routine exercise (engine.md §4.8): the policy in force, the
/// decision (`off | first | up | hold | deload`), the fields it sets and the `why` template.
Prescription nextPrescription(TrainingState state, RoutineExercise cfg, [Routine? routine]) {
  final catalog = state.catalog;
  final mode = modeOf(catalog, cfg);
  final policy = policyFor(catalog, cfg, routine, mode);
  final unit = state.unit.isEmpty ? 'kg' : state.unit;
  final inc = incrementFor(catalog, cfg, unit);
  if (policy == 'off') return Prescription(policy: policy, kind: 'off');

  final sessions = sessionsFor(state, cfg.id, cfg).where((s) => s.mode == mode).toList();
  if (sessions.isEmpty) return Prescription(policy: policy, kind: 'first', why: [WhyTemplate.first]);
  if (_planTargetChanged(state, cfg, mode)) {
    return Prescription(policy: policy, kind: 'first', why: [WhyTemplate.targetChanged]);
  }

  final last = sessions.last;
  final deloadAt = deloadAfter[policy] ?? 3;
  final stalls = stallsFor(policy, mode, sessions);

  if (last is TimeSession) {
    final goal = numOr(last.goal, numOr(cfg.sec, 0));
    if (last.ok) {
      return Prescription(policy: policy, kind: 'up', sec: normNum(goal + inc), why: [WhyTemplate.timeUp, inc]);
    }
    if (stalls >= deloadAt) {
      final sec = _deloadTo(goal, inc > 0 ? inc : defaultSecIncrement); // engine-Q2
      return Prescription(policy: policy, kind: 'deload', sec: sec, why: [WhyTemplate.timeDeload, stalls, sec]);
    }
    return Prescription(
      policy: policy,
      kind: 'hold',
      sec: jsTruthy(last.goal) ? last.goal : cfg.sec,
      why: [WhyTemplate.timeHold],
    );
  }

  final session = last as RepsSession;
  final w = session.weight;

  // Bodyweight work progresses in reps under every policy and never deloads.
  if (w <= 0) {
    final goal = numOr(session.goal, numOr(cfg.reps, 0));
    if (session.ok && goal > 0) {
      return Prescription(
        policy: policy,
        kind: 'up',
        weight: 0,
        reps: goal + 1,
        why: [WhyTemplate.bodyweightUp, goal + 1],
      );
    }
    return Prescription(
      policy: policy,
      kind: 'hold',
      weight: 0,
      reps: goal == 0 ? null : goal,
      why: [WhyTemplate.bodyweightHold],
    );
  }

  if (policy == 'double') {
    final top = numOr(cfg.reps, numOr(session.goal, 10));
    final bottom = min(numOr(cfg.repsMin, max(1, top - 2)), top);
    if (session.ok) {
      return Prescription(
        policy: policy,
        kind: 'up',
        weight: _snap(w + inc, inc),
        reps: bottom,
        why: [WhyTemplate.doubleUp, inc, unit, bottom],
      );
    }
    if (stalls >= deloadAt) {
      final dw = _deloadTo(w, inc);
      return Prescription(
        policy: policy,
        kind: 'deload',
        weight: dw,
        reps: bottom,
        why: [WhyTemplate.doubleDeload, stalls, dw, unit],
      );
    }
    final aim = min(top, max(bottom, session.low + 1));
    return Prescription(policy: policy, kind: 'hold', weight: w, reps: aim, why: [WhyTemplate.doubleHold, aim]);
  }

  // Linear and Greyskull.
  if (session.ok) {
    final doubleJump = policy == 'greyskull' && session.goal > 0 && session.amrap >= session.goal * 2;
    final step = normNum(doubleJump ? inc * 2 : inc);
    return Prescription(
      policy: policy,
      kind: 'up',
      weight: _snap(w + step, inc),
      why: doubleJump ? [WhyTemplate.greyskullDoubleJump, session.amrap, step, unit] : [WhyTemplate.up, step, unit],
    );
  }
  if (stalls >= deloadAt) {
    final dw = _deloadTo(w, inc);
    return Prescription(
      policy: policy,
      kind: 'deload',
      weight: dw,
      why: stalls > 1 ? [WhyTemplate.deloadRunning, stalls, dw, unit] : [WhyTemplate.deloadOnce, dw, unit],
    );
  }
  return Prescription(policy: policy, kind: 'hold', weight: w, why: [WhyTemplate.hold, deloadAt - stalls, deloadAt]);
}

/// Writes the decided fields into the sets not yet done. `off`, `first` and no prescription
/// return [sets] itself; done sets are kept as the same instances.
List<SetRecord> applyPrescription(List<SetRecord> sets, Prescription? p) {
  if (p == null || p.kind == 'off' || p.kind == 'first') return sets;
  return [
    for (final s in sets)
      if (s.done)
        s
      else
        s.copy()
          ..w = p.weight ?? s.w
          ..r = p.reps ?? s.r
          ..sec = p.sec ?? s.sec,
  ];
}
