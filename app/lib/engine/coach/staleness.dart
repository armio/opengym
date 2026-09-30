/// Staleness (specs/coach.md §7.2): which changes of a proposal can still be applied to the live
/// plan. Recomputed against the plan whenever the proposal is shown or applied.
library;

import 'package:collection/collection.dart';

import '../../data/models/json.dart';
import '../../data/models/plan.dart';
import '../../data/models/proposal.dart';
import '../catalog.dart';
import '../js.dart';
import 'plan_hash.dart';

/// Change types about one scalar the plan holds; the others are structural.
const _scalarTypes = {
  'sets',
  'reps',
  'repsMin',
  'sec',
  'inc',
  'exercise-prog',
  'routine-prog',
  'rename-routine',
  'week',
};

/// Whether [type] is about a single value of the plan (see [currentValue]).
bool isScalarChange(String type) => _scalarTypes.contains(type);

Routine? _routine(PlanDoc plan, JsonMap target) {
  final id = target['routineId'];
  return jsTruthy(id) ? plan.routineById(jsString(id)) : null;
}

RoutineExercise? _exercise(Routine? routine, Object? exId) =>
    routine?.ex.firstWhereOrNull((e) => e.id == jsString(exId));

/// The plan's current value for what a scalar change is about — what its `before` is checked
/// against — or null when unset. Structural changes have none: see [isScalarChange].
Object? currentValue(PlanDoc plan, JsonMap change) {
  final target = asMap(change['target']);
  final routine = _routine(plan, target);
  final exercise = jsTruthy(target['exId']) ? _exercise(routine, target['exId']) : null;
  return switch (change['type']) {
    'sets' => exercise?.sets,
    'reps' => exercise?.reps,
    'repsMin' => exercise?.repsMin,
    'sec' => exercise?.sec,
    'inc' => exercise?.inc,
    'exercise-prog' => exercise?.prog,
    'routine-prog' => routine?.prog,
    'rename-routine' => routine?.name,
    'week' => target['weekday'] == null ? null : plan.week[jsString(target['weekday'])],
    _ => null,
  };
}

/// JavaScript's `===` on two JSON scalars.
bool _same(Object? a, Object? b) => (a is num || b is num) ? a is num && b is num && a == b : a == b;

/// One change of a proposal checked against the live plan.
class ReviewedChange {
  const ReviewedChange(this.change, {required this.stale});

  final ProposalChange change;

  /// The routine or exercise it names is gone, or its value was already changed by hand —
  /// applying it would overwrite that edit. Shown greyed out and never applied.
  final bool stale;

  String get id => change.id;
}

/// A `changes` proposal checked against the live plan (`markStale`).
class ReviewedProposal {
  const ReviewedProposal({required this.proposal, required this.planMoved, required this.changes});

  final Proposal proposal;

  /// The plan changed since Claude read it (it only drives a banner; fresh changes still apply).
  final bool planMoved;

  /// Every change, in proposal order.
  final List<ReviewedChange> changes;

  /// The changes that can be applied — the ones ticked by default.
  List<ReviewedChange> get applicable => [
    for (final c in changes)
      if (!c.stale) c,
  ];
}

/// Checks every change of [proposal] against [plan]. [library] resolves exercise modes for the
/// plan fingerprint (the plan's own custom exercises are added).
ReviewedProposal markStale(Proposal proposal, PlanDoc plan, ExerciseIndex library) {
  final hash = proposal.planHash;
  final planMoved = hash != null && hash.isNotEmpty && hash != planHash(plan, library);
  return ReviewedProposal(
    proposal: proposal,
    planMoved: planMoved,
    changes: [for (final c in proposal.changes) ReviewedChange(c, stale: _isStale(plan, c))],
  );
}

bool _isStale(PlanDoc plan, ProposalChange change) {
  final raw = change.raw;
  final target = asMap(raw['target']);
  final routine = _routine(plan, target);
  final type = change.type;
  if (type != 'add-routine' && type != 'week' && routine == null) return true;
  if (jsTruthy(target['exId']) && _exercise(routine, target['exId']) == null) return true;
  if (!isScalarChange(type)) return false;
  final current = currentValue(plan, raw);
  final before = raw['before'];
  return before != null && current != null && !_same(current, before);
}
