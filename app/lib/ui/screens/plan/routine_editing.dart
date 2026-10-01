/// The plan edits of the Plan tab and the routine editor (specs/data-model.md §2.5.2), as pure
/// functions over the models so they can be tested without widgets. Callers run them inside
/// `AppState.updatePlan` / `updateSchedule`.
library;

import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../widgets/routine_icon.dart' show defaultGlyph;

/// Name of a routine created with "Nueva".
const newRoutineName = 'Nueva rutina';

/// What an emptied routine name is stored as.
const fallbackRoutineName = 'Rutina';

/// A new empty routine with a fresh id (not added to [plan]).
Routine newRoutine(PlanDoc plan, DateTime now) =>
    Routine(id: freshId(now, (id) => plan.routineById(id) != null), name: newRoutineName, emoji: defaultGlyph);

/// The routine name stored for what the name field holds (every keystroke): trimmed, or "Rutina".
String routineNameFor(String input) {
  final name = input.trim();
  return name.isEmpty ? fallbackRoutineName : name;
}

/// `move(i, dir)`: swaps entry [i] with its neighbour in direction [dir] (ignored at the ends),
/// then drops superset tags left without an adjacent partner.
void moveRoutineExercise(List<RoutineExercise> ex, int i, int dir) {
  final j = i + dir;
  if (i < 0 || i >= ex.length || j < 0 || j >= ex.length) return;
  final moved = ex[i];
  ex[i] = ex[j];
  ex[j] = moved;
  cleanupSg(ex);
}

/// `toggleLink(i)`: entry [i] leaves the superset of the one above if they share one; otherwise
/// it joins the group of the one above, or both start a group with [newTag] (a unique
/// `'sg' + uid` — coach-B3). Then orphaned tags are dropped, so unlinking the middle of a chain
/// A-B-C dissolves the whole chain.
void toggleSupersetLink(List<RoutineExercise> ex, int i, String Function() newTag) {
  if (i < 1 || i >= ex.length) return;
  final cur = ex[i], prev = ex[i - 1];
  if (_tagged(cur.sg) && _tagged(prev.sg) && cur.sg == prev.sg) {
    cur.sg = null;
  } else {
    final group = _tagged(prev.sg) ? prev.sg! : newTag();
    prev.sg = group;
    cur.sg = group;
  }
  cleanupSg(ex);
}

bool _tagged(String? sg) => sg != null && sg.isNotEmpty;

/// A superset tag no routine of [plan] uses yet.
String newSupersetTag(PlanDoc plan, DateTime now) =>
    freshId(now, (id) => plan.routines.any((r) => r.ex.any((e) => e.sg == id)), prefix: 'sg');

/// Whether entry [i] is linked to the one above (the link button's "on" state).
bool isLinkedToPrevious(List<RoutineExercise> ex, int i) =>
    i > 0 && i < ex.length && _tagged(ex[i].sg) && ex[i - 1].sg == ex[i].sg;

/// The superset layout of a routine: the first index of every multi-member unit (where the
/// "Superserie" label goes) and every index inside one (the accent bar).
({Set<int> firsts, Set<int> members}) supersetLayout(List<RoutineExercise> ex) {
  final groups = supersetUnits([for (final e in ex) e.sg]).where((u) => u.length > 1);
  return (firsts: {for (final u in groups) u.first}, members: {for (final u in groups) ...u});
}

/// Replaces entry [i] with a config saved by the config sheet, keeping only its `id` and `sg`.
void replaceRoutineExercise(List<RoutineExercise> ex, int i, RoutineExercise saved) {
  if (i < 0 || i >= ex.length) return;
  ex[i] = saved.copy()
    ..id = ex[i].id
    ..sg = ex[i].sg;
}

/// Removes entry [i] and cleans up the superset it leaves.
void removeRoutineExercise(List<RoutineExercise> ex, int i) {
  if (i < 0 || i >= ex.length) return;
  ex.removeAt(i);
  cleanupSg(ex);
}

/// `S.week` edit: [routineId] trains on [weekday] (0 = Sunday), or null for a rest day.
void assignWeekday(PlanDoc plan, int weekday, String? routineId) {
  if (routineId == null || routineId.isEmpty) {
    plan.week.remove('$weekday');
  } else {
    plan.week['$weekday'] = routineId;
  }
}

/// `dayPlan` edit for [iso]: a routine id, `'rest'`, or null / `''` to follow the week again.
void rescheduleDate(ScheduleDoc schedule, String iso, String? value) {
  if (value == null || value.isEmpty) {
    schedule.dayPlan.remove(iso);
  } else {
    schedule.dayPlan[iso] = value;
  }
}
