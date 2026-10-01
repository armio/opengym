/// Dart port of `frontend/src/lib/coach.test.js` (specs/coach.md §11), adapted to the port:
/// proposals are `Proposal` DTOs, apply works on the plan and coach docs of a draft, and the
/// contract fixes (coach-B3, coach-B5, coach-Q10, coach-Q12, the mode rule) have tests of their own.
/// Gating and consent are gone from the port (contract §6), so their cases are not ported.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

final library = indexWith();
final now = DateTime.utc(2026, 9, 30, 8);

JsonMap _planJson() => {
  'routines': [
    {
      'id': 'r1',
      'name': 'Full body A',
      'emoji': '💪',
      'prog': 'linear',
      'ex': [
        {'id': '0001', 'sets': 3, 'reps': 10, 'mode': 'reps', 'weight': 20, 'prog': 'linear'},
        {'id': '0007', 'sets': 3, 'sec': 45, 'mode': 'time'},
        {'id': '0009', 'sets': 3, 'reps': 12, 'mode': 'reps'},
      ],
    },
    {
      'id': 'r2',
      'name': 'Full body B',
      'ex': [
        {'id': '0002', 'sets': 4, 'reps': 6, 'mode': 'reps'},
      ],
    },
  ],
  'week': {'1': 'r1', '3': 'r2', '5': 'r1'},
  'customEx': <dynamic>[],
};

/// coach.test.js `state()`: the plan doc of the fixture.
PlanDoc state([void Function(PlanDoc plan)? edit]) {
  final plan = PlanDoc.fromJson(_planJson());
  edit?.call(plan);
  return plan;
}

JsonMap change([JsonMap over = const {}]) => {
  'id': 'c1',
  'type': 'sets',
  'target': {'routineId': 'r1', 'exId': '0001'},
  'before': 3,
  'after': 4,
  'why': 'stalled twice',
  ...over,
};

Proposal proposal(List<JsonMap> changes, [JsonMap over = const {}]) => Proposal.fromJson({
  'id': 'p1',
  'kind': 'changes',
  'status': 'pending',
  'summary': 's',
  'changes': changes,
  ...over,
});

/// Applies against a throwaway draft, the way the Coach screen does.
PlanDoc apply(PlanDoc plan, Proposal p, List<String> ids) {
  final draft = plan.copy();
  applyChangeSet(draft, CoachDoc(), p, ids, library: library, now: now);
  return draft;
}

List<String> ids(Routine r) => [for (final e in r.ex) e.id];

final bundle = {
  'opengym_plan': 1,
  'name': 'Coach plan',
  'summary': 'three days',
  'week': {'1': 'x1', '3': 'x2'},
  'routines': [
    {
      'id': 'x1',
      'name': 'A',
      'emoji': '💪',
      'why': 'why A',
      'ex': [
        {'id': '0001', 'sets': 3, 'reps': 10, 'mode': 'reps', 'why': 'why ex'},
      ],
    },
    {
      'id': 'x2',
      'name': 'B',
      'emoji': '🏋️',
      'ex': [
        {'id': '0002', 'sets': 3, 'reps': 8, 'mode': 'reps'},
      ],
    },
  ],
  'customEx': <dynamic>[],
};

Proposal planProposal([JsonMap? b]) => Proposal.fromJson({
  'id': 'p1',
  'kind': 'plan',
  'status': 'pending',
  'summary': 'three days',
  'bundle': b ?? bundle,
});

void main() {
  group('plan fingerprint', () {
    test('ignores nothing that matters and reacts to nothing that does not', () {
      final s = state();
      expect(planHash(s, library), planHash(state(), library));
      // A field the plan does not carry cannot move the hash.
      expect(planHash(state((p) => p.extra['theme'] = 'light'), library), planHash(s, library));
      expect(
        planHash(state((p) => p.customEx.add(CustomExercise(id: 'c1', n: 'x', bp: 'back'))), library),
        planHash(s, library),
      );
      // Everything the Coach can change does.
      expect(planHash(state((p) => p.routines[0].ex[0].sets = 4), library), isNot(planHash(s, library)));
      expect(planHash(state((p) => p.week['6'] = 'r1'), library), isNot(planHash(s, library)));
    });

    test('cannot tell "no weight" from "0 kg" — both mean unloaded', () {
      expect(
        planHash(state((p) => p.routines[0].ex[2].weight = null), library),
        planHash(state((p) => p.routines[0].ex[2].weight = 0), library),
      );
    });

    test('agrees with the server on the golden fixtures', () {
      expect(planHash(state(), library), 'f784c8ca82c205eb');
      expect(planHash(state((p) => p.week.clear()), library), 'd619a67e9451fd3f');
      expect(planHash(state((p) => p.routines.clear()), library), '14115d860381e569');
    });
  });

  group('staleness', () {
    test('flags the whole proposal when the plan moved underneath it', () {
      final p = proposal([change()], {'planHash': planHash(state(), library)});
      expect(markStale(p, state(), library).planMoved, isFalse);
      expect(markStale(p, state((s) => s.routines[0].ex[0].sets = 5), library).planMoved, isTrue);
      // Without a stored hash there is nothing to compare.
      expect(markStale(proposal([change()]), state((s) => s.routines[0].ex[0].sets = 5), library).planMoved, isFalse);
    });

    test('flags a change whose target is gone', () {
      final s = state((p) => p.routines[0].ex.removeWhere((e) => e.id == '0001'));
      expect(markStale(proposal([change()]), s, library).changes.single.stale, isTrue);
    });

    test('flags a change someone already made by hand, rather than overwriting them', () {
      final s = state((p) => p.routines[0].ex[0].sets = 5); // Claude saw 3, the owner has since set 5
      final reviewed = markStale(proposal([change()]), s, library);
      expect(reviewed.changes.single.stale, isTrue);
      expect(reviewed.applicable, isEmpty);
    });

    test('leaves an untouched change applicable', () {
      expect(markStale(proposal([change()]), state(), library).changes.single.stale, isFalse);
    });

    test('compares strictly: a string "3" is not the number 3', () {
      expect(
        markStale(
          proposal([
            change({'before': '3'}),
          ]),
          state(),
          library,
        ).changes.single.stale,
        isTrue,
      );
    });

    test('a null before or an unset value never marks a change stale', () {
      expect(
        markStale(
          proposal([
            change({'before': null}),
          ]),
          state(),
          library,
        ).changes.single.stale,
        isFalse,
      );
      expect(
        markStale(
          proposal([
            change({'type': 'inc', 'before': 2.5, 'after': 5}),
          ]),
          state(),
          library,
        ).changes.single.stale,
        isFalse,
      );
    });

    test('reads the current value for every scalar change type', () {
      final s = state();
      expect(currentValue(s, change({'type': 'sets'})), 3);
      expect(currentValue(s, change({'type': 'reps'})), 10);
      expect(currentValue(s, change({'type': 'exercise-prog'})), 'linear');
      expect(currentValue(s, change({'type': 'routine-prog'})), 'linear');
      expect(
        currentValue(
          s,
          change({
            'type': 'week',
            'target': {'weekday': 1},
          }),
        ),
        'r1',
      );
    });
  });

  group('applying changes', () {
    test('sets, reps, rep floor, hold time, load step and policies', () {
      final s = state();
      expect(
        apply(
          s,
          proposal([
            change({'type': 'sets', 'after': 4}),
          ]),
          ['c1'],
        ).routines[0].ex[0].sets,
        4,
      );
      expect(
        apply(
          s,
          proposal([
            change({'type': 'reps', 'before': 10, 'after': 12}),
          ]),
          ['c1'],
        ).routines[0].ex[0].reps,
        12,
      );
      expect(
        apply(
          s,
          proposal([
            change({'type': 'repsMin', 'before': null, 'after': 8}),
          ]),
          ['c1'],
        ).routines[0].ex[0].repsMin,
        8,
      );
      expect(
        apply(
          s,
          proposal([
            change({
              'type': 'sec',
              'target': {'routineId': 'r1', 'exId': '0007'},
              'before': 45,
              'after': 60,
            }),
          ]),
          ['c1'],
        ).routines[0].ex[1].sec,
        60,
      );
      expect(
        apply(
          s,
          proposal([
            change({'type': 'inc', 'before': null, 'after': 5}),
          ]),
          ['c1'],
        ).routines[0].ex[0].inc,
        5,
      );
      expect(
        apply(
          s,
          proposal([
            change({'type': 'exercise-prog', 'before': 'linear', 'after': 'double'}),
          ]),
          ['c1'],
        ).routines[0].ex[0].prog,
        'double',
      );
      expect(
        apply(
          s,
          proposal([
            change({
              'type': 'routine-prog',
              'target': {'routineId': 'r1'},
              'before': 'linear',
              'after': 'greyskull',
            }),
          ]),
          ['c1'],
        ).routines[0].prog,
        'greyskull',
      );
    });

    test('adds an exercise at the position asked for', () {
      final out = apply(
        state(),
        proposal([
          change({
            'type': 'add-exercise',
            'target': {'routineId': 'r1'},
            'before': null,
            'after': {'id': '0002', 'sets': 3, 'reps': 8, 'mode': 'reps', 'position': 1},
          }),
        ]),
        ['c1'],
      );
      expect(ids(out.routines[0]), ['0001', '0002', '0007', '0009']);
      expect(out.routines[0].ex[1].sets, 3);
      expect(out.routines[0].ex[1].reps, 8);
    });

    test('drops an exercise without touching the rest', () {
      final out = apply(
        state(),
        proposal([
          change({'type': 'remove-exercise'}),
        ]),
        ['c1'],
      );
      expect(ids(out.routines[0]), ['0007', '0009']);
    });

    test('keeps the prescription when swapping the movement', () {
      final out = apply(
        state(),
        proposal([
          change({
            'type': 'swap-exercise',
            'after': {'id': '0002'},
          }),
        ]),
        ['c1'],
      );
      final e = out.routines[0].ex[0];
      expect(e.id, '0002');
      expect(e.sets, 3);
      expect(e.reps, 10); // not silently reset — that would be a change nobody approved
      expect(e.prog, 'linear');
    });

    test('reorders only with a complete permutation', () {
      final out = apply(
        state(),
        proposal([
          change({
            'type': 'reorder',
            'target': {'routineId': 'r1'},
            'after': ['0009', '0001', '0007'],
          }),
        ]),
        ['c1'],
      );
      expect(ids(out.routines[0]), ['0009', '0001', '0007']);
      expect(
        () => apply(
          state(),
          proposal([
            change({
              'type': 'reorder',
              'target': {'routineId': 'r1'},
              'after': ['0009'],
            }),
          ]),
          ['c1'],
        ),
        throwsA(isA<ProposalException>()),
      );
      // A duplicate is not a permutation either (coach-Q7).
      expect(
        () => apply(
          state(),
          proposal([
            change({
              'type': 'reorder',
              'target': {'routineId': 'r1'},
              'after': ['0009', '0009', '0001'],
            }),
          ]),
          ['c1'],
        ),
        throwsA(isA<ProposalException>()),
      );
    });

    test('supersets by moving the partner adjacent and tagging both', () {
      final out = apply(
        state(),
        proposal([
          change({
            'type': 'superset',
            'after': {'link': true, 'with': '0009'},
          }),
        ]),
        ['c1'],
      );
      final ex = out.routines[0].ex;
      expect(ex[0].id, '0001');
      expect(ex[1].id, '0009');
      expect(ex[0].sg, isNotNull);
      expect(ex[0].sg, ex[1].sg);
      expect(ex[2].sg, isNull);
    });

    test('unlinks a superset and cleans up the orphan tag', () {
      final s = state((p) {
        p.routines[0].ex[0].sg = 'a';
        p.routines[0].ex[1].sg = 'a';
      });
      final out = apply(
        s,
        proposal([
          change({
            'type': 'superset',
            'after': {'link': false},
          }),
        ]),
        ['c1'],
      );
      expect(out.routines[0].ex[0].sg, isNull);
      expect(out.routines[0].ex[1].sg, isNull);
    });

    test('a superset with itself is refused (coach-Q8)', () {
      expect(
        () => apply(
          state(),
          proposal([
            change({
              'type': 'superset',
              'after': {'link': true, 'with': '0001'},
            }),
          ]),
          ['c1'],
        ),
        throwsA(isA<ProposalException>()),
      );
    });

    test('adds, renames and removes routines, clearing any day that pointed at one', () {
      final added = apply(
        state(),
        proposal([
          change({
            'type': 'add-routine',
            'target': <String, dynamic>{},
            'before': null,
            'after': {
              'name': 'Full body C',
              'ex': [
                {'id': '0001', 'sets': 3, 'reps': 10, 'mode': 'reps'},
              ],
            },
          }),
        ]),
        ['c1'],
      );
      expect(added.routines, hasLength(3));
      expect(added.routines[2].id, isNot('r1'));
      expect(added.routines[2].name, 'Full body C');
      expect(added.routines[2].emoji, '🏋️');

      final renamed = apply(
        state(),
        proposal([
          change({
            'type': 'rename-routine',
            'target': {'routineId': 'r1'},
            'before': 'Full body A',
            'after': 'Upper',
          }),
        ]),
        ['c1'],
      );
      expect(renamed.routines[0].name, 'Upper');

      final removed = apply(
        state(),
        proposal([
          change({
            'type': 'remove-routine',
            'target': {'routineId': 'r2'},
          }),
        ]),
        ['c1'],
      );
      expect([for (final r in removed.routines) r.id], ['r1']);
      expect(removed.week['3'], isNull); // Wednesday pointed at r2
    });

    test('moves a day, and clears one', () {
      final moved = apply(
        state(),
        proposal([
          change({
            'type': 'week',
            'target': {'weekday': 6},
            'before': null,
            'after': 'r1',
          }),
        ]),
        ['c1'],
      );
      expect(moved.week['6'], 'r1');
      final cleared = apply(
        state(),
        proposal([
          change({
            'type': 'week',
            'target': {'weekday': 1},
            'before': 'r1',
            'after': 'rest',
          }),
        ]),
        ['c1'],
      );
      expect(cleared.week.containsKey('1'), isFalse);
    });

    test('touches nothing but the routines and the week', () {
      final s = state((p) {
        p.customEx.add(CustomExercise(id: 'cx', n: 'Sandbag carry', bp: 'back'));
        p.extra['future'] = {'kept': true};
      });
      final out = apply(
        s,
        proposal([
          change({'type': 'sets', 'after': 4}),
        ]),
        ['c1'],
      );
      expect(
        jsonEncode([for (final c in out.customEx) c.toJson()]),
        jsonEncode([for (final c in s.customEx) c.toJson()]),
      );
      expect(out.extra, s.extra);
    });
  });

  group('contract fixes', () {
    test('a missing mode defaults by body part: cardio keeps its duration and pace', () {
      final out = apply(
        state(),
        proposal([
          change({
            'type': 'add-exercise',
            'target': {'routineId': 'r1'},
            'before': null,
            'after': {'id': '3220', 'sets': 1, 'min': 25, 'speed': 9},
          }),
        ]),
        ['c1'],
      );
      final e = out.routines[0].ex.last;
      expect(e.toJson(), {'id': '3220', 'sets': 1, 'mode': 'cardio', 'min': 25, 'speed': 9});
    });

    test('add-routine keeps cardio min and speed and writes every mode (coach-B5)', () {
      final out = apply(
        state(),
        proposal([
          change({
            'type': 'add-routine',
            'target': <String, dynamic>{},
            'before': null,
            'after': {
              'name': 'Cardio',
              'prog': 'linear',
              'ex': [
                {'id': '3220', 'sets': 1, 'min': 30, 'speed': 9.5},
                {'id': '0001', 'sets': 3, 'reps': 12},
                {'id': '0007', 'sets': 2, 'mode': 'time', 'sec': 40},
              ],
            },
          }),
        ]),
        ['c1'],
      );
      final r = out.routines.last;
      expect(r.prog, 'linear');
      expect(
        [for (final e in r.ex) e.toJson()],
        [
          {'id': '3220', 'sets': 1, 'mode': 'cardio', 'min': 30, 'speed': 9.5},
          {'id': '0001', 'sets': 3, 'mode': 'reps', 'reps': 12},
          {'id': '0007', 'sets': 2, 'mode': 'time', 'sec': 40},
        ],
      );
    });

    test('a swap drops the old movement\'s weight unless one is given (coach-Q12)', () {
      final dropped = apply(
        state(),
        proposal([
          change({
            'type': 'swap-exercise',
            'after': {'id': '0002'},
          }),
        ]),
        ['c1'],
      );
      expect(dropped.routines[0].ex[0].weight, 0);
      final given = apply(
        state(),
        proposal([
          change({
            'type': 'swap-exercise',
            'after': {'id': '0002', 'weight': 12.5},
          }),
        ]),
        ['c1'],
      );
      expect(given.routines[0].ex[0].weight, 12.5);
      final unloaded = apply(
        state(),
        proposal([
          change({
            'type': 'swap-exercise',
            'target': {'routineId': 'r1', 'exId': '0009'},
            'after': {'id': '0002'},
          }),
        ]),
        ['c1'],
      );
      expect(unloaded.routines[0].ex[2].toJson().containsKey('weight'), isFalse);
    });

    test('two supersets in one change set get their own tags (coach-B3)', () {
      final s = state((p) => p.routines[0].ex.add(RoutineExercise(id: '0025', sets: 3, reps: 8)));
      final out = apply(
        s,
        proposal([
          change({
            'id': 'c1',
            'type': 'superset',
            'after': {'link': true, 'with': '0007'},
          }),
          change({
            'id': 'c2',
            'type': 'superset',
            'target': {'routineId': 'r1', 'exId': '0009'},
            'after': {'link': true, 'with': '0025'},
          }),
        ]),
        ['c1', 'c2'],
      );
      final ex = out.routines[0].ex;
      expect(ids(out.routines[0]), ['0001', '0007', '0009', '0025']);
      expect(ex[0].sg, ex[1].sg);
      expect(ex[2].sg, ex[3].sg);
      expect(ex[0].sg, isNot(ex[2].sg));
    });

    test('a ticked change that no longer fits is reported and logged as stale (coach-Q10)', () {
      final draft = state();
      final coach = CoachDoc();
      final result = applyChangeSet(
        draft,
        coach,
        proposal([
          change({'id': 'c1', 'type': 'sets', 'after': 4}),
          change({
            'id': 'c2',
            'type': 'reps',
            'target': {'routineId': 'r1', 'exId': 'ghost'},
            'before': null,
            'after': 12,
          }),
          change({'id': 'c3', 'type': 'reps', 'before': 10, 'after': 11}),
        ]),
        ['c1', 'c2'],
        library: library,
        now: now,
      );
      expect(result.applied, ['c1']);
      expect(result.rejected, ['c3']);
      expect(result.stale, ['c2']);
      final decisions = logDecisions(coach.log.last);
      // Applied first (with target, before and after), then declined, then stale.
      expect([for (final d in decisions) '${d['id']}:${d['status']}'], ['c1:accepted', 'c3:rejected', 'c2:stale']);
      expect(decisions.first['before'], 3);
      expect(decisions.first['after'], 4);
      expect(decisions.first['target'], {'routineId': 'r1', 'exId': '0001'});
    });
  });

  group('accepting a subset', () {
    test('applies only what was accepted and records the rest as declined', () {
      final draft = state();
      final coach = CoachDoc();
      final result = applyChangeSet(
        draft,
        coach,
        proposal([
          change({'id': 'c1', 'type': 'sets', 'after': 4}),
          change({'id': 'c2', 'type': 'reps', 'before': 10, 'after': 12}),
        ]),
        ['c1'],
        library: library,
        now: now,
      );
      expect(result.applied, ['c1']);
      expect(result.rejected, ['c2']);
      expect(draft.routines[0].ex[0].sets, 4);
      expect(draft.routines[0].ex[0].reps, 10);
      final c2 = logDecisions(coach.log.last).firstWhere((d) => d['id'] == 'c2');
      expect(c2['status'], 'rejected');
      expect(coach.lastReview, {'at': now.millisecondsSinceEpoch});
    });

    test('refuses to apply a stale change even if it was ticked', () {
      final draft = state((p) => p.routines[0].ex.clear());
      final coach = CoachDoc();
      final result = applyChangeSet(draft, coach, proposal([change()]), ['c1'], library: library, now: now);
      expect(result.applied, isEmpty);
      expect(result.isEmpty, isTrue);
      // Nothing to apply: no snapshot, no log, no review time.
      expect(coach.snapshots, isEmpty);
      expect(coach.log, isEmpty);
      expect(coach.lastReview, isNull);
    });

    test('is all-or-nothing: a failure part-way leaves the live plan exactly as it was', () {
      final live = state();
      final before = jsonEncode(live.toJson());
      final p = proposal([
        change({'id': 'c1', 'type': 'sets', 'after': 4}),
        change({
          'id': 'c2',
          'type': 'reorder',
          'target': {'routineId': 'r1'},
          'before': null,
          'after': ['0009'],
        }),
      ]);
      // The draft is a copy; throwing means the caller discards it.
      final draft = live.copy();
      expect(
        () => applyChangeSet(draft, CoachDoc(), p, ['c1', 'c2'], library: library, now: now),
        throwsA(isA<ProposalException>()),
      );
      expect(jsonEncode(live.toJson()), before);
    });
  });

  group('snapshots and revert', () {
    test('puts the plan back and logs the revert', () {
      final draft = state();
      final coach = CoachDoc();
      final original = jsonEncode([for (final r in draft.routines) r.toJson()]);
      applyChangeSet(
        draft,
        coach,
        proposal([
          change({'type': 'sets', 'after': 4}),
        ]),
        ['c1'],
        library: library,
        now: now,
      );
      expect(draft.routines[0].ex[0].sets, 4);
      expect(canRevert(coach), isTrue);
      final later = now.add(const Duration(minutes: 5));
      final snapshot = revertLast(draft, coach, now: later);
      expect(snapshot, isNotNull);
      expect(snapshot!.proposalId, 'p1');
      expect(jsonEncode([for (final r in draft.routines) r.toJson()]), original);
      expect(coach.snapshots, isEmpty);
      final entry = coach.log.last;
      expect(entry['kind'], 'revert');
      expect(entry['proposalId'], 'p1');
      expect(entry['snapshotAt'], snapshot.at);
      expect(entry['at'], later.millisecondsSinceEpoch);
      expect(entry['summary'], revertSummary);
    });

    test('keeps a bounded number of snapshots', () {
      final plan = state();
      final coach = CoachDoc();
      for (var i = 0; i < snapshotMax + 3; i++) {
        pushSnapshot(plan, coach, proposalId: 'p$i', now: now);
      }
      expect(coach.snapshots, hasLength(snapshotMax));
      expect(coach.snapshots.last.proposalId, 'p${snapshotMax + 2}');
    });

    test('reverting with nothing to revert to is a no-op, not a crash', () {
      expect(revertLast(state(), CoachDoc(), now: now), isNull);
    });
  });

  group('the log', () {
    test('is bounded', () {
      final coach = CoachDoc();
      for (var i = 0; i < logMax + 10; i++) {
        appendLog(coach, {'kind': 'review', 'at': i, 'summary': 's$i'}, now: now);
      }
      expect(coach.log, hasLength(logMax));
      expect(coach.log.last['summary'], 's${logMax + 9}');
      expect(coach.log.last['id'], isA<String>());
    });

    test('stays well inside the sync budget even when full', () {
      final plan = state();
      final coach = CoachDoc();
      for (var i = 0; i < logMax; i++) {
        appendLog(coach, {
          'kind': 'review',
          'at': i,
          'summary': 'x' * 200,
          'decisions': [
            {'id': 'c', 'type': 'sets', 'why': 'y' * 200, 'status': 'accepted'},
          ],
        }, now: now);
      }
      for (var i = 0; i < snapshotMax; i++) {
        pushSnapshot(plan, coach, proposalId: 'p$i', now: now);
      }
      expect(jsonStringify(coach.toJson()).length, lessThan(300 * 1024));
    });

    test('trims the oldest history once the doc outgrows 256 KiB', () {
      final plan = state();
      final coach = CoachDoc();
      for (var i = 0; i < logMax; i++) {
        appendLog(coach, {'kind': 'review', 'at': i, 'summary': 'z' * 8000}, now: now);
      }
      expect(jsonStringify(coach.toJson()).length, lessThanOrEqualTo(coachDocMaxLength));
      expect(coach.log.length, lessThan(logMax));
      expect(coach.log.last['at'], logMax - 1);
      pushSnapshot(plan, coach, proposalId: 'p', now: now);
      expect(coach.snapshots, hasLength(1));
    });

    test('records a dismissal so a later review knows not to nag', () {
      final coach = CoachDoc();
      recordDismissal(
        coach,
        proposal([
          change(),
          change({'id': 'c2'}),
        ]),
        stale: {'c2'},
        now: now,
      );
      final entry = coach.log.last;
      expect(entry['kind'], 'review');
      expect(entry['dismissed'], isTrue);
      expect([for (final d in logDecisions(entry)) d['status']], ['rejected', 'stale']);
      expect(coach.lastReview, {'at': now.millisecondsSinceEpoch});
    });

    test('a dismissed plan is logged as a create and is not a review', () {
      final coach = CoachDoc();
      recordDismissal(coach, planProposal(), now: now);
      expect(coach.log.last['kind'], 'create');
      expect(coach.log.last['decisions'], isEmpty);
      expect(coach.lastReview, isNull);
    });
  });

  group('created plans', () {
    test('adds routines as new ones and never modifies what was already there', () {
      final draft = state();
      final coach = CoachDoc();
      expect(applyCreatedPlan(draft, coach, planProposal(), schedule: false, now: now), 2);
      expect(draft.routines, hasLength(4));
      expect(draft.routines[0].name, 'Full body A'); // untouched
      expect(draft.routines[2].id, isNot('x1')); // fresh ids, like a plan import
      expect(draft.week['1'], 'r1'); // schedule left alone
      final entry = coach.log.last;
      expect(entry['kind'], 'create');
      expect(entry['routines'], 2);
      expect(entry['iteration'], 1);
      expect(coach.snapshots.single.label, snapshotLabelPlan);
      expect(coach.lastReview, isNull);
    });

    test('replaces the week only when asked, and remaps to the new ids', () {
      final draft = state();
      applyCreatedPlan(draft, CoachDoc(), planProposal(), schedule: true, now: now);
      expect(draft.week['1'], draft.routines[2].id);
      expect(draft.week['3'], draft.routines[3].id);
      expect(draft.week.containsKey('5'), isFalse); // a day the new plan leaves empty is rest
    });

    test('keeps Claude\'s prose out of the routine data', () {
      final draft = state();
      applyCreatedPlan(draft, CoachDoc(), planProposal(), schedule: false, now: now);
      final json = draft.routines[2].toJson();
      expect(json.containsKey('why'), isFalse);
      expect(asMap(asList(json['ex']).first).containsKey('why'), isFalse);
      expect(asMap(asList(json['ex']).first).containsKey('name'), isFalse);
      expect(draft.routines[2].ex.first.mode, 'reps');
    });

    test('is revertible like any other change', () {
      final draft = state();
      final coach = CoachDoc();
      applyCreatedPlan(draft, coach, planProposal(), schedule: true, now: now);
      revertLast(draft, coach, now: now);
      expect(draft.routines, hasLength(2));
      expect(draft.week['1'], 'r1');
    });

    test('brings custom exercises along in the full shape and remaps them', () {
      final draft = state();
      applyCreatedPlan(
        draft,
        CoachDoc(),
        planProposal({
          ...bundle,
          'routines': [
            {
              'id': 'x1',
              'name': 'A',
              'ex': [
                {'id': 'cx1', 'sets': 3, 'reps': 10, 'mode': 'reps'},
              ],
            },
          ],
          'customEx': [
            {'id': 'cx1', 'n': 'Sandbag carry', 'bp': 'back'},
          ],
        }),
        schedule: false,
        now: now,
      );
      expect(draft.customEx, hasLength(1));
      final custom = draft.customEx.single;
      expect(draft.routines[2].ex[0].id, custom.id);
      expect(custom.id, startsWith('c'));
      expect(custom.toJson(), {
        'id': custom.id,
        'n': 'Sandbag carry',
        'bp': 'back',
        'desc': '',
        'tg': '',
        'eq': 'custom',
        'custom': true,
      });
    });

    test('reuses a custom exercise with the same name and body part', () {
      final draft = state((p) => p.customEx.add(CustomExercise(id: 'cMine', n: 'sandbag CARRY', bp: 'back')));
      applyCreatedPlan(
        draft,
        CoachDoc(),
        planProposal({
          ...bundle,
          'routines': [
            {
              'id': 'x1',
              'name': '',
              'ex': [
                {'id': 'cx1', 'sets': 3, 'reps': 10, 'mode': 'reps'},
              ],
            },
          ],
          'customEx': [
            {'id': 'cx1', 'n': 'Sandbag carry', 'bp': 'back'},
          ],
        }),
        schedule: false,
        now: now,
      );
      expect(draft.customEx, hasLength(1));
      expect(draft.routines[2].ex[0].id, 'cMine');
      expect(draft.routines[2].name, sharedRoutineName);
    });
  });

  group('validation', () {
    test('rejects an unreadable proposal rather than half-applying it', () {
      final unreadable = throwsA(
        isA<ProposalException>().having((e) => e.message, 'message', 'Esa propuesta no se puede leer.'),
      );
      expect(() => validateProposal(Proposal.fromJson(null)), unreadable);
      expect(() => validateProposal(Proposal.fromJson(<String, dynamic>{})), unreadable);
      expect(
        () => validateProposal(
          proposal([
            {'type': 'drop-database'},
          ]),
        ),
        unreadable,
      );
      expect(() => validateProposal(planProposal({'routines': <dynamic>[]})), unreadable);
      expect(() => validateProposal(proposal([change()])), returnsNormally);
      expect(() => validateProposal(planProposal()), returnsNormally);
    });
  });

  group('display', () {
    test('titles every change type in Spanish', () {
      String title(JsonMap c) => changeTitle(change(c), library);
      expect(
        title({
          'type': 'add-exercise',
          'after': {'id': '0025'},
        }),
        'Añadir barbell bench press',
      );
      expect(title({'type': 'remove-exercise'}), 'Quitar 3/4 sit-up');
      expect(
        title({
          'type': 'swap-exercise',
          'after': {'id': '0025'},
        }),
        'Cambiar 3/4 sit-up por barbell bench press',
      );
      expect(title({'type': 'sets'}), '3/4 sit-up: series');
      expect(title({'type': 'reps'}), '3/4 sit-up: repeticiones');
      expect(title({'type': 'repsMin'}), '3/4 sit-up: mínimo del rango de repeticiones');
      expect(title({'type': 'sec'}), '3/4 sit-up: tiempo de sostén');
      expect(title({'type': 'cardio'}), '3/4 sit-up: duración y ritmo');
      expect(title({'type': 'inc'}), '3/4 sit-up: incremento de carga');
      expect(title({'type': 'exercise-prog'}), '3/4 sit-up: progresión');
      expect(title({'type': 'routine-prog'}), 'Progresión de la rutina');
      expect(title({'type': 'reorder'}), 'Reordenar ejercicios');
      expect(
        title({
          'type': 'superset',
          'after': {'link': true, 'with': '0025'},
        }),
        'Superserie de 3/4 sit-up con barbell bench press',
      );
      expect(
        title({
          'type': 'superset',
          'after': {'link': false},
        }),
        'Deshacer la superserie de 3/4 sit-up',
      );
      expect(
        title({
          'type': 'add-routine',
          'after': {'name': 'Pierna'},
        }),
        'Añadir rutina «Pierna»',
      );
      expect(title({'type': 'remove-routine'}), 'Eliminar una rutina');
      expect(title({'type': 'rename-routine', 'after': 'Torso'}), 'Renombrar la rutina a «Torso»');
      expect(title({'type': 'week'}), 'Cambiar lo planificado en un día');
      expect(
        title({
          'type': 'add-exercise',
          'after': {'id': 'nope'},
        }),
        'Añadir Ejercicio desconocido',
      );
    });

    test('shows before and after values, none for structural changes', () {
      ({String before, String after})? values(JsonMap c) =>
          changeValues(change(c), library, routineName: (id) => id == 'r1' ? 'Full body A' : null);
      expect(values({'type': 'add-exercise'}), isNull);
      expect(values({'type': 'reorder'}), isNull);
      expect(values({'type': 'remove-routine'}), isNull);
      expect(values({'type': 'sets'}), (before: '3', after: '4'));
      expect(values({'type': 'inc', 'before': null, 'after': 2.5}), (before: '—', after: '2,5'));
      expect(values({'type': 'exercise-prog', 'before': 'linear', 'after': 'double'}), (
        before: 'Progresión lineal',
        after: 'Progresión doble',
      ));
      expect(values({'type': 'week', 'before': null, 'after': 'r1'}), (before: 'Descanso', after: 'Full body A'));
      expect(
        values({
          'type': 'swap-exercise',
          'before': {'id': '0001'},
          'after': {'id': '0025'},
        }),
        (before: '3/4 sit-up', after: 'barbell bench press'),
      );
      expect(
        values({
          'type': 'cardio',
          'before': {'min': 20},
          'after': {'min': 30, 'speed': 8.5},
        }),
        (before: '20 min', after: '30 min @ 8,5 km/h'),
      );
    });

    test('labels log entries and decisions', () {
      expect(logEntryTitle({'kind': 'create'}), 'Creó un plan');
      expect(logEntryTitle({'kind': 'revert'}), 'Deshizo los últimos cambios');
      expect(logEntryTitle({'kind': 'review'}), 'Revisó tu entrenamiento');
      expect(
        appliedCount({
          'decisions': [
            {'status': 'accepted'},
            {'status': 'rejected'},
            {'status': 'accepted'},
          ],
        }),
        2,
      );
      expect(decisionLabel('accepted'), 'aplicado');
      expect(decisionLabel('rejected'), 'rechazado');
      expect(decisionLabel('stale'), 'no aplicable');
      expect(applyButtonLabel(0), 'No aplicar nada');
      expect(applyButtonLabel(1), 'Aplicar 1 cambio');
      expect(applyButtonLabel(3), 'Aplicar 3 cambios');
    });
  });
}
