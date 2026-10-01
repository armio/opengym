/// The Push / Pull / Legs starter plan (specs/data-model.md §5.1, contract §6 with data-B12).
library;

import '../data/models/plan.dart';
import 'format.dart';

/// One starter routine: Spanish name, the English name older plans used, icon key and
/// `[exercise id, sets, reps]` rows.
typedef _StarterSpec = ({String name, String english, String emoji, List<(String, int, int)> ex});

const List<_StarterSpec> _spec = [
  (
    name: 'Empuje',
    english: 'Push Day',
    emoji: 'barbell',
    ex: [('0025', 4, 8), ('0047', 3, 10), ('0426', 3, 10), ('0334', 3, 12), ('0241', 3, 12), ('0251', 3, 10)],
  ),
  (
    name: 'Tirón',
    english: 'Pull Day',
    emoji: 'pullup',
    ex: [('2330', 4, 10), ('0027', 4, 8), ('1323', 3, 10), ('0031', 3, 10), ('0313', 3, 12)],
  ),
  (
    name: 'Pierna',
    english: 'Leg Day',
    emoji: 'legs',
    ex: [('0043', 4, 8), ('0085', 3, 10), ('0739', 3, 12), ('0585', 3, 12), ('0586', 3, 12), ('0605', 4, 15)],
  ),
];

/// Weekdays the starter routines are scheduled on: Monday push, Wednesday pull, Friday legs.
const _starterDays = ['1', '3', '5'];

/// Toast shown after loading the starter plan.
const starterPlanLoadedMessage = 'Plan inicial cargado — Lun Empuje · Mié Tirón · Vie Pierna';

/// Loads the starter plan into [plan] (data-B12): each routine is created only when no routine
/// with its Spanish or English name (case-insensitive) exists — otherwise that one is reused —
/// and Monday / Wednesday / Friday always point at the three. Returns the routines created.
List<Routine> loadStarterPlan(PlanDoc plan, {required DateTime now}) {
  final created = <Routine>[];
  for (final (i, spec) in _spec.indexed) {
    final names = {spec.name.toLowerCase(), spec.english.toLowerCase()};
    var routine = plan.routines.where((r) => names.contains(r.name.toLowerCase())).firstOrNull;
    if (routine == null) {
      routine = Routine(
        id: freshId(now, (id) => plan.routineById(id) != null),
        name: spec.name,
        emoji: spec.emoji,
        ex: [for (final (id, sets, reps) in spec.ex) RoutineExercise(id: id, sets: sets, reps: reps, weight: 0)],
      );
      plan.routines.add(routine);
      created.add(routine);
    }
    plan.week[_starterDays[i]] = routine.id;
  }
  return created;
}
