import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';
import 'package:opengym/ui/screens/plan/routine_editing.dart';

/// Entries named by their ids, with optional superset tags: `ex('a', 'b:g1', 'c:g1')`.
List<RoutineExercise> ex(List<String> specs) => [
  for (final s in specs) RoutineExercise(id: s.split(':').first, sg: s.contains(':') ? s.split(':').last : null),
];

List<String> ids(List<RoutineExercise> ex) => [for (final e in ex) e.id];
List<String?> tags(List<RoutineExercise> ex) => [for (final e in ex) e.sg];

void main() {
  var counter = 0;
  String tag() => 'sgT${counter++}';
  setUp(() => counter = 0);

  group('move (specs/ui.md §3.4)', () {
    test('swaps with the neighbour and ignores the ends', () {
      final list = ex(['a', 'b', 'c']);
      moveRoutineExercise(list, 0, -1);
      expect(ids(list), ['a', 'b', 'c']);
      moveRoutineExercise(list, 2, 1);
      expect(ids(list), ['a', 'b', 'c']);
      moveRoutineExercise(list, 0, 1);
      expect(ids(list), ['b', 'a', 'c']);
      moveRoutineExercise(list, 2, -1);
      expect(ids(list), ['b', 'c', 'a']);
    });

    test('moving a member out of a pair breaks the pair', () {
      final list = ex(['a:g', 'b:g', 'c']);
      moveRoutineExercise(list, 1, 1);
      expect(ids(list), ['a', 'c', 'b']);
      expect(tags(list), [null, null, null]);
    });

    test('moving inside a three-chain keeps the members that stay adjacent', () {
      final list = ex(['a:g', 'b:g', 'c:g', 'd']);
      moveRoutineExercise(list, 2, 1);
      expect(ids(list), ['a', 'b', 'd', 'c']);
      expect(tags(list), ['g', 'g', null, null]);
    });
  });

  group('superset link toggle (coach-B3)', () {
    test('links with the entry above under a fresh unique tag, then unlinks', () {
      final list = ex(['a', 'b', 'c']);
      toggleSupersetLink(list, 1, tag);
      expect(tags(list), ['sgT0', 'sgT0', null]);
      expect(isLinkedToPrevious(list, 1), isTrue);

      toggleSupersetLink(list, 1, tag);
      expect(tags(list), [null, null, null], reason: 'a partnerless tag is cleaned up too');
    });

    test('each new link gets its own tag; joining an existing group reuses it', () {
      final list = ex(['a', 'b', 'c', 'd']);
      toggleSupersetLink(list, 1, tag);
      toggleSupersetLink(list, 3, tag);
      expect(tags(list), ['sgT0', 'sgT0', 'sgT1', 'sgT1']);

      // c joins the group above; its old partner d is left alone and loses its tag.
      toggleSupersetLink(list, 2, tag);
      expect(tags(list), ['sgT0', 'sgT0', 'sgT0', null]);
      expect(counter, 2);
    });

    test('unlinking the middle of a three-chain dissolves the whole chain', () {
      final list = ex(['a', 'b', 'c']);
      toggleSupersetLink(list, 1, tag);
      toggleSupersetLink(list, 2, tag);
      expect(tags(list), ['sgT0', 'sgT0', 'sgT0']);

      toggleSupersetLink(list, 1, tag);
      expect(tags(list), [null, null, null]);
    });

    test('the first entry has no link', () {
      final list = ex(['a', 'b']);
      toggleSupersetLink(list, 0, tag);
      expect(tags(list), [null, null]);
      expect(counter, 0);
    });

    test('newSupersetTag is unique across the whole plan', () {
      final plan = PlanDoc(
        routines: [
          Routine(id: 'r', name: 'R', ex: ex(['a:sgX', 'b:sgX'])),
        ],
      );
      final now = DateTime(2026, 9, 30);
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        final t = newSupersetTag(plan, now);
        expect(t, startsWith('sg'));
        expect(t, isNot('sgX'));
        plan.routines.first.ex.add(RoutineExercise(id: 'x$i', sg: t));
        expect(seen.add(t), isTrue);
      }
    });
  });

  test('supersetLayout marks the first member of each multi-member unit and every member', () {
    final layout = supersetLayout(ex(['a', 'b:g', 'c:g', 'd', 'e:h', 'f:h', 'g:h', 'h:i']));
    expect(layout.firsts, {1, 4});
    expect(layout.members, {1, 2, 4, 5, 6});
  });

  test('replace keeps only the id and sg of the entry; remove cleans up the superset', () {
    final list = ex(['a', 'b:g', 'c:g']);
    replaceRoutineExercise(
      list,
      1,
      RoutineExercise(id: 'zzz', sets: 5, mode: 'reps', reps: 6, weight: 80, sg: 'other'),
    );
    expect(list[1].toJson(), {'id': 'b', 'sets': 5, 'mode': 'reps', 'reps': 6, 'weight': 80, 'sg': 'g'});

    removeRoutineExercise(list, 2);
    expect(ids(list), ['a', 'b']);
    expect(tags(list), [null, null]);
  });

  test('routine names: trimmed, or "Rutina" when empty; new routines are "Nueva rutina"', () {
    expect(routineNameFor('  Torso  '), 'Torso');
    expect(routineNameFor('   '), 'Rutina');
    final plan = PlanDoc();
    final r = newRoutine(plan, DateTime(2026, 9, 30));
    expect(r.name, 'Nueva rutina');
    expect(r.emoji, 'figureStrength');
    expect(r.ex, isEmpty);
  });

  test('weekday assignment and date reschedules', () {
    final plan = PlanDoc();
    assignWeekday(plan, 1, 'r1');
    assignWeekday(plan, 0, 'r2');
    expect(plan.week, {'1': 'r1', '0': 'r2'});
    assignWeekday(plan, 1, null);
    assignWeekday(plan, 0, '');
    expect(plan.week, isEmpty);

    final schedule = ScheduleDoc();
    rescheduleDate(schedule, '2026-09-30', 'r1');
    rescheduleDate(schedule, '2026-10-01', 'rest');
    expect(schedule.dayPlan, {'2026-09-30': 'r1', '2026-10-01': 'rest'});
    rescheduleDate(schedule, '2026-09-30', '');
    rescheduleDate(schedule, '2026-10-01', null);
    expect(schedule.dayPlan, isEmpty);
  });

  test('starter plan: Monday/Wednesday/Friday, no duplicates when loaded twice (data-B12)', () {
    final plan = PlanDoc(
      routines: [Routine(id: 'old', name: 'push day', emoji: 'arm')],
    );
    final created = loadStarterPlan(plan, now: DateTime(2026, 9, 30));
    expect([for (final r in created) r.name], ['Tirón', 'Pierna'], reason: '"push day" is reused');
    expect(plan.week['1'], 'old');
    expect(plan.routineById(plan.week['3'])!.name, 'Tirón');
    expect(plan.routineById(plan.week['5'])!.name, 'Pierna');

    plan.week.clear();
    expect(loadStarterPlan(plan, now: DateTime(2026, 9, 30)), isEmpty);
    expect(plan.routines, hasLength(3));
    expect(plan.week.keys, unorderedEquals(['1', '3', '5']));
  });
}
