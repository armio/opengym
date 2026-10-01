/// Accepting a proposal (specs/coach.md §7.6–§7.7, contract §4.3). The functions mutate the
/// `plan` and `coach` docs of a **draft** (`AppState.beginProposalDraft()`); when one throws, the
/// caller discards the draft and nothing is sent, which is what makes accepting atomic.
library;

import 'package:collection/collection.dart';

import '../../data/models/coach_doc.dart';
import '../../data/models/json.dart';
import '../../data/models/plan.dart';
import '../../data/models/proposal.dart';
import '../catalog.dart';
import '../format.dart';
import '../js.dart';
import 'changes.dart';
import 'coach_log.dart';
import 'staleness.dart';

/// Name given to a routine of a plan bundle that has none.
const sharedRoutineName = 'Rutina compartida';

/// The ids a resolution reports (`POST /api/proposals/:id/resolve`).
class ChangeSetResult {
  const ChangeSetResult({required this.applied, required this.rejected, required this.stale});

  /// Applied — the resolution's `accepted`.
  final List<String> applied;

  /// Applicable but not accepted by the owner.
  final List<String> rejected;

  /// No longer applicable to the plan, ticked or not (coach-Q10): neither applied nor declined.
  final List<String> stale;

  bool get isEmpty => applied.isEmpty;
}

/// Applies the accepted, still-applicable changes of a `changes` proposal to [plan], in proposal
/// order (specs/coach.md §7.6). Staleness is re-checked against [plan] first, so a change that
/// no longer fits is never applied.
///
/// With something to apply: snapshots the plan, applies every change (a throw leaves the draft
/// half-edited — discard it), logs a `review` entry whose decisions are the applied changes (with
/// target, before, after), the declined ones and the stale ones, and sets `lastReview`. With
/// nothing to apply, [plan] and [coach] are untouched — dismiss the proposal instead.
ChangeSetResult applyChangeSet(
  PlanDoc plan,
  CoachDoc coach,
  Proposal proposal,
  Iterable<String> acceptedIds, {
  required ExerciseIndex library,
  required DateTime now,
}) {
  validateProposal(proposal);
  final reviewed = markStale(proposal, plan, library);
  final accepted = acceptedIds.toSet();
  final toApply = [
    for (final c in reviewed.changes)
      if (accepted.contains(c.id) && !c.stale) c.change,
  ];
  final result = ChangeSetResult(
    applied: [for (final c in toApply) c.id],
    rejected: [
      for (final c in reviewed.changes)
        if (!accepted.contains(c.id) && !c.stale) c.id,
    ],
    stale: [
      for (final c in reviewed.changes)
        if (c.stale) c.id,
    ],
  );
  if (toApply.isEmpty) return result;

  pushSnapshot(plan, coach, proposalId: proposal.id, label: snapshotLabelChanges, now: now);
  final catalog = library.withCustoms(plan.customEx);
  for (final c in toApply) {
    applyChange(plan, c.raw, catalog: catalog, now: now);
  }

  JsonMap brief(ProposalChange c, String status) => {'id': c.id, 'type': c.type, 'why': c.why, 'status': status};
  final byId = {for (final c in proposal.changes) c.id: c};
  final at = now.millisecondsSinceEpoch;
  appendLog(coach, {
    'kind': 'review',
    'at': at,
    'proposalId': proposal.id,
    'summary': proposal.summary,
    'evidence': proposal.evidence,
    'notes': proposal.notes,
    'decisions': [
      for (final c in toApply)
        {
          'id': c.id,
          'type': c.type,
          'target': deepCopyJson(c.raw['target']),
          'before': deepCopyJson(c.before),
          'after': deepCopyJson(c.after),
          'why': c.why,
          'status': 'accepted',
        },
      for (final id in result.rejected) brief(byId[id]!, 'rejected'),
      for (final id in result.stale) brief(byId[id]!, 'stale'),
    ],
  }, now: now);
  coach.lastReview = {'at': at};
  return result;
}

/// Accepts a `plan` proposal (specs/coach.md §7.7): snapshots the plan, adds the bundle's
/// routines as new ones (existing routines and history are never touched), replaces the week
/// only when [schedule] is on, and logs a `create` entry. `lastReview` is not touched. Returns
/// the number of routines added.
int applyCreatedPlan(PlanDoc plan, CoachDoc coach, Proposal proposal, {required bool schedule, required DateTime now}) {
  validateProposal(proposal);
  pushSnapshot(plan, coach, proposalId: proposal.id, label: snapshotLabelPlan, now: now);
  final bundle = proposal.bundleJson!;
  // Claude's `why` texts are for the review screen; they have no place in the routine data.
  final stripped = {
    ...bundle,
    'routines': [
      for (final r in asList(bundle['routines']))
        if (r is Map)
          {
            ...asMap(r)..remove('why'),
            'ex': [
              for (final e in asList(r['ex']))
                if (e is Map)
                  asMap(e)
                    ..remove('why')
                    ..remove('name'),
            ],
          },
    ],
  };
  final added = mergePlan(plan, stripped, schedule: schedule, now: now);
  appendLog(coach, {
    'kind': 'create',
    'at': now.millisecondsSinceEpoch,
    'proposalId': proposal.id,
    'summary': proposal.summary,
    'routines': added,
    'iteration': proposal.iteration,
  }, now: now);
  return added;
}

/// Plan-import semantics (`mergePlan`): the bundle's custom exercises are matched to existing
/// ones by name (case-insensitive) and body part or created in the full shape (data-B3); its
/// routines always arrive as new routines with fresh ids and exercise ids remapped; with
/// [schedule], the week is replaced wholesale (days the bundle leaves empty become rest).
/// Returns the number of routines added.
int mergePlan(PlanDoc plan, Map<dynamic, dynamic> bundle, {required bool schedule, required DateTime now}) {
  final exIds = <String, String>{};
  for (final raw in asList(bundle['customEx'])) {
    if (raw is! Map) continue;
    final c = asMap(raw);
    final name = asString(c['n']) ?? '';
    final bodyPart = asString(c['bp']) ?? '';
    final same = plan.customEx.firstWhereOrNull((x) => x.n.toLowerCase() == name.toLowerCase() && x.bp == bodyPart);
    final id = same?.id ?? freshId(now, (id) => plan.customById(id) != null, prefix: 'c');
    if (same == null) plan.customEx.add(CustomExercise(id: id, n: name, bp: bodyPart, desc: asString(c['desc']) ?? ''));
    exIds[jsString(c['id'])] = id;
  }

  final routineIds = <String, String>{};
  final routines = [
    for (final r in asList(bundle['routines']))
      if (r is Map) asMap(r),
  ];
  for (final r in routines) {
    final id = freshId(now, (id) => plan.routineById(id) != null);
    routineIds[jsString(r['id'])] = id;
    plan.routines.add(
      Routine(
        id: id,
        name: jsTruthy(r['name']) ? jsString(r['name']) : sharedRoutineName,
        emoji: asString(r['emoji']),
        prog: jsTruthy(r['prog']) ? jsString(r['prog']) : null,
        ex: [
          for (final e in asList(r['ex']))
            if (e is Map) RoutineExercise.fromJson({...asMap(e), 'id': exIds[jsString(e['id'])] ?? e['id']}),
        ],
      ),
    );
  }

  if (schedule) {
    for (var d = 0; d < 7; d++) {
      plan.week.remove('$d');
    }
    asMap(bundle['week']).forEach((day, oldId) {
      final id = routineIds[jsString(oldId)];
      if (id != null) plan.week[day] = id;
    });
  }
  return routines.length;
}
