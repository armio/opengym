/// The closed list of plan changes Claude can propose and how each one edits the plan
/// (specs/coach.md §4.4 and §7.5, with coach-B3, coach-B5, coach-Q12 and the mode rule of
/// contract §5.3). A type without an entry here can never take effect.
library;

import '../../data/models/json.dart';
import '../../data/models/plan.dart';
import '../../data/models/proposal.dart';
import '../catalog.dart';
import '../format.dart';
import '../history.dart';
import '../js.dart';
import '../progression.dart';

/// A proposal that cannot be read or applied. [message] is Spanish, ready for a toast.
class ProposalException implements Exception {
  const ProposalException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _unreadable = ProposalException('Esa propuesta no se puede leer.');
const _missingTarget = ProposalException('El cambio se refiere a una rutina o un ejercicio que ya no está en tu plan.');
const _missingPartner = ProposalException('El compañero de superserie ya no está en la rutina.');
const _incompleteReorder = ProposalException('El nuevo orden no incluye cada ejercicio de la rutina una vez.');
const _invalidValue = ProposalException('El cambio trae un valor no válido.');

/// Default icon of a routine Claude adds without one.
const defaultRoutineEmoji = '🏋️';

/// Every change type, in the original's order.
const changeTypes = [
  'add-exercise', 'remove-exercise', 'swap-exercise', 'sets', 'reps', 'repsMin', 'sec', 'cardio', 'inc', //
  'exercise-prog', 'routine-prog', 'reorder', 'superset', 'add-routine', 'remove-routine', 'rename-routine', 'week',
];

/// The client-side gate: a `plan` proposal needs a non-empty bundle, a `changes` proposal a
/// list of changes of known types. Throws a [ProposalException] otherwise.
void validateProposal(Proposal proposal) {
  final bundle = proposal.bundleJson;
  if (bundle != null) {
    final routines = bundle['routines'];
    if (routines is! List || routines.isEmpty) throw _unreadable;
    return;
  }
  final changes = proposal.extra['changes'];
  if (changes is! List) throw _unreadable;
  for (final c in changes) {
    if (c is! Map || !changeTypes.contains(c['type'])) throw _unreadable;
  }
}

/// Applies one change to [plan] in place. [catalog] must know the plan's custom exercises (a
/// missing mode defaults by body part). Throws a [ProposalException] when the change no longer
/// fits the plan; the caller then discards the whole draft.
void applyChange(PlanDoc plan, JsonMap change, {required ExerciseIndex catalog, required DateTime now}) {
  final apply = _appliers[change['type']];
  if (apply == null) throw _unreadable;
  apply(_Change(plan, change, catalog, now));
}

/// One change being applied, with lookups that throw when their target is gone (`need`).
class _Change {
  _Change(this.plan, this.raw, this.catalog, this.now) : target = asMap(raw['target']);

  final PlanDoc plan;
  final JsonMap raw;
  final ExerciseIndex catalog;
  final DateTime now;
  final JsonMap target;

  Object? get after => raw['after'];
  JsonMap get afterMap => asMap(raw['after']);
  String? get exId => asString(target['exId']);

  Routine get routine => plan.routineById(asString(target['routineId'])) ?? (throw _missingTarget);

  int get exerciseIndex {
    final i = routine.ex.indexWhere((e) => e.id == exId);
    return i < 0 ? throw _missingTarget : i;
  }

  RoutineExercise get exercise => routine.ex[exerciseIndex];

  num get afterNum => asNum(after) ?? (throw _invalidValue);
  String get afterString => asString(after) ?? (throw _invalidValue);

  String newRoutineId() => freshId(now, (id) => plan.routineById(id) != null);
}

int _intOr(Object? value, int fallback) {
  final n = asNum(value);
  return n == null || n == 0 ? fallback : n.round();
}

/// A new routine exercise with the prescription defaults of its mode. A missing mode is cardio
/// exactly for cardio body parts (contract §5.3); cardio keeps its duration and speed (coach-B5).
RoutineExercise _newExercise(ExerciseIndex catalog, JsonMap a) {
  final id = asString(a['id']) ?? (throw _invalidValue);
  final mode = modeFor(catalog, mode: a['mode'], id: id);
  final e = RoutineExercise(id: id, sets: _intOr(a['sets'], 3), mode: mode);
  switch (mode) {
    case ExerciseMode.cardio:
      e.min = numOr(asNum(a['min']), 20);
      e.speed = numOr(asNum(a['speed']), 8);
    case ExerciseMode.time:
      e.sec = numOr(asNum(a['sec']), 45);
    default:
      e.reps = numOr(asNum(a['reps']), 10);
  }
  return e;
}

final Map<String, void Function(_Change c)> _appliers = {
  'add-exercise': (c) {
    final r = c.routine;
    final a = c.afterMap;
    final e = _newExercise(c.catalog, a);
    final weight = asNum(a['weight']);
    if (weight != null && weight > 0) e.weight = weight;
    if (policies.contains(a['prog'])) e.prog = a['prog'] as String;
    final position = asInt(a['position']);
    r.ex.insert(position == null ? r.ex.length : position.clamp(0, r.ex.length), e);
    cleanupSg(r.ex);
  },
  'remove-exercise': (c) {
    final r = c.routine;
    r.ex.removeWhere((e) => e.id == c.exId);
    cleanupSg(r.ex);
  },
  'swap-exercise': (c) {
    final r = c.routine;
    final i = c.exerciseIndex;
    final a = c.afterMap;
    final swapped = r.ex[i].copy()..id = asString(a['id']) ?? (throw _invalidValue);
    // Keep the prescription unless Claude changed it — a swap is about the movement — but never
    // carry the old movement's load over (coach-Q12).
    if (jsTruthy(a['sets'])) swapped.sets = _intOr(a['sets'], swapped.sets);
    if (jsTruthy(a['reps'])) swapped.reps = asNum(a['reps']);
    final weight = asNum(a['weight']);
    swapped.weight = weight != null && weight > 0 ? weight : (swapped.weight == null ? null : 0);
    r.ex[i] = swapped;
  },
  'sets': (c) => c.exercise.sets = c.afterNum.round(),
  'reps': (c) => c.exercise.reps = c.afterNum,
  'repsMin': (c) => c.exercise.repsMin = c.afterNum,
  'sec': (c) => c.exercise.sec = c.afterNum,
  'inc': (c) => c.exercise.inc = c.afterNum,
  'exercise-prog': (c) => c.exercise.prog = c.afterString,
  'cardio': (c) {
    final e = c.exercise;
    final a = c.afterMap;
    if (asNum(a['min']) case final min?) e.min = min;
    if (asNum(a['speed']) case final speed?) e.speed = speed;
  },
  'routine-prog': (c) => c.routine.prog = c.afterString,
  'reorder': (c) {
    final r = c.routine;
    final after = c.after;
    final order = after is List ? [for (final id in after) jsString(id)] : (throw _invalidValue);
    final byId = {for (final e in r.ex) e.id: e};
    final next = [for (final id in order) ?byId[id]];
    if (next.length != r.ex.length || order.toSet().length != order.length) throw _incompleteReorder;
    r.ex = next;
    cleanupSg(r.ex);
  },
  'superset': (c) {
    final r = c.routine;
    final i = c.exerciseIndex;
    final a = c.afterMap;
    if (!jsTruthy(a['link'])) {
      r.ex[i].sg = null;
      cleanupSg(r.ex);
      return;
    }
    final partnerId = asString(a['with']);
    final j = r.ex.indexWhere((e) => e.id == partnerId);
    if (j < 0 || partnerId == c.exId) throw _missingPartner;
    // Supersets are adjacency: move the partner right after the exercise, then tag both with a
    // tag of their own (coach-B3) and drop any tag the move orphaned.
    final partner = r.ex.removeAt(j);
    final at = r.ex.indexWhere((e) => e.id == c.exId);
    r.ex.insert(at + 1, partner);
    final tag = freshId(c.now, (t) => r.ex.any((e) => e.sg == t), prefix: 'sg');
    r.ex[at].sg = tag;
    r.ex[at + 1].sg = tag;
    cleanupSg(r.ex);
  },
  'add-routine': (c) {
    final a = c.afterMap;
    final exercises = a['ex'];
    if (exercises is! List) throw _invalidValue;
    c.plan.routines.add(
      Routine(
        id: c.newRoutineId(),
        name: asString(a['name']) ?? (throw _invalidValue),
        emoji: jsTruthy(a['emoji']) ? jsString(a['emoji']) : defaultRoutineEmoji,
        prog: policies.contains(a['prog']) ? a['prog'] as String : null,
        ex: [
          for (final e in exercises)
            if (e is Map) _newExercise(c.catalog, asMap(e)),
        ],
      ),
    );
  },
  'remove-routine': (c) {
    final id = asString(c.target['routineId']);
    c.plan.routines.removeWhere((r) => r.id == id);
    // A day pointing at a routine that no longer exists reads as rest anyway; clear it.
    c.plan.week.removeWhere((_, routineId) => routineId == id);
  },
  'rename-routine': (c) => c.routine.name = c.afterString,
  'week': (c) {
    final weekday = asInt(c.target['weekday']) ?? (throw _invalidValue);
    final after = c.after;
    if (after == null || after == 'rest') {
      c.plan.week.remove('$weekday');
    } else {
      c.plan.week['$weekday'] = c.afterString;
    }
  },
};
