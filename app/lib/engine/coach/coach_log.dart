/// The coach doc's memory (specs/coach.md §7.4, §7.8, §7.9): plan snapshots for revert, the
/// decision log, and the size guard that keeps the doc under its sync budget.
library;

import '../../data/models/coach_doc.dart';
import '../../data/models/json.dart';
import '../../data/models/plan.dart';
import '../../data/models/proposal.dart';
import '../format.dart';
import '../js.dart';

/// Snapshots kept for revert.
const snapshotMax = 3;

/// Log entries kept.
const logMax = 50;

/// Upper bound of the coach doc's JSON, in UTF-16 code units (256 KiB).
const coachDocMaxLength = 256 * 1024;

/// Snapshot label before an accepted plan proposal.
const snapshotLabelPlan = 'Antes del plan del Coach';

/// Snapshot label before accepted plan changes.
const snapshotLabelChanges = 'Antes de los cambios del Coach';

/// Summary of the log entry a revert writes.
const revertSummary = 'Se deshicieron los últimos cambios del Coach.';

/// Remembers [plan]'s routines and week (not its custom exercises) before a proposal touches
/// them. Keeps the newest [snapshotMax].
void pushSnapshot(PlanDoc plan, CoachDoc coach, {String? proposalId, String label = '', required DateTime now}) {
  coach.snapshots.add(
    CoachSnapshot(
      at: now.millisecondsSinceEpoch,
      proposalId: proposalId,
      label: label,
      routines: [for (final r in plan.routines) r.copy()],
      week: {...plan.week},
    ),
  );
  if (coach.snapshots.length > snapshotMax) coach.snapshots.removeRange(0, coach.snapshots.length - snapshotMax);
  trimCoach(coach);
}

/// Appends [entry] to the log (with a fresh `id` unless it has one), keeping the newest [logMax].
void appendLog(CoachDoc coach, JsonMap entry, {required DateTime now}) {
  coach.log.add({
    'id': jsTruthy(entry['id']) ? entry['id'] : uid(now),
    for (final e in entry.entries)
      if (e.key != 'id') e.key: deepCopyJson(e.value),
  });
  if (coach.log.length > logMax) coach.log.removeRange(0, coach.log.length - logMax);
  trimCoach(coach);
}

/// The last line of defence for the sync budget: while the doc's JSON is over
/// [coachDocMaxLength], drop the oldest snapshot, then the oldest log entry (at most 60 steps,
/// always keeping one of each).
void trimCoach(CoachDoc coach) {
  for (var guard = 0; guard < 60 && jsonStringify(coach.toJson()).length > coachDocMaxLength; guard++) {
    if (coach.snapshots.length > 1) {
      coach.snapshots.removeAt(0);
    } else if (coach.log.length > 1) {
      coach.log.removeAt(0);
    } else {
      break;
    }
  }
}

/// Whether there is a snapshot to go back to.
bool canRevert(CoachDoc coach) => coach.snapshots.isNotEmpty;

/// Puts [plan]'s routines and week back as they were before the last applied proposal, pops
/// that snapshot and logs the revert (with `snapshotAt`). Workouts, custom exercises and
/// reschedules are untouched. Returns the snapshot — its `proposalId` is the proposal to revert
/// on the server — or null when there is nothing to undo.
CoachSnapshot? revertLast(PlanDoc plan, CoachDoc coach, {required DateTime now}) {
  if (coach.snapshots.isEmpty) return null;
  final snapshot = coach.snapshots.removeLast();
  plan.routines = [for (final r in snapshot.routines) r.copy()];
  plan.week = {...snapshot.week};
  appendLog(coach, {
    'kind': 'revert',
    'at': now.millisecondsSinceEpoch,
    'proposalId': snapshot.proposalId,
    'snapshotAt': snapshot.at,
    'summary': revertSummary,
  }, now: now);
  return snapshot;
}

/// Records a proposal turned down whole, so a later review knows not to propose it again.
/// Changes in [stale] (no longer applicable, see `markStale`) are logged as such rather than as
/// declined. A dismissed `changes` proposal also counts as a review.
void recordDismissal(CoachDoc coach, Proposal proposal, {Set<String> stale = const {}, required DateTime now}) {
  final isPlan = proposal.kind == Proposal.kindPlan;
  appendLog(coach, {
    'kind': isPlan ? 'create' : 'review',
    'at': now.millisecondsSinceEpoch,
    'proposalId': proposal.id,
    'summary': proposal.summary,
    'dismissed': true,
    'decisions': [
      for (final c in proposal.changes)
        {'id': c.id, 'type': c.type, 'why': c.why, 'status': stale.contains(c.id) ? 'stale' : 'rejected'},
    ],
  }, now: now);
  if (!isPlan) coach.lastReview = {'at': now.millisecondsSinceEpoch};
}
