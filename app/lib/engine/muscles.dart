/// Port of `muscles.js` (specs/engine.md §7): which muscles an exercise trains and how much
/// work each got, in "effective sets" (the weight is deliberately ignored).
library;

import 'dart:math';

import '../data/models/active_workout.dart';
import '../data/models/plan.dart';
import '../data/models/workout.dart';
import 'catalog.dart';

/// The 18 drawable muscles, head to toe (the body map's slugs).
const muscles = [
  'trapezius', 'deltoids', 'chest', 'upper-back', 'serratus', //
  'biceps', 'triceps', 'forearm',
  'abs', 'obliques', 'lower-back',
  'gluteal', 'quadriceps', 'hamstring', 'adductors', 'hip-flexors',
  'calves', 'tibialis',
];

/// Body-map parts drawn as silhouette only.
const inertBodyParts = ['head', 'hair', 'neck', 'hands', 'feet', 'knees', 'ankles'];

/// Spanish display name of each muscle (`MUSCLE_NAME` through es.js).
const muscleNames = {
  'trapezius': 'Trapecio',
  'deltoids': 'Hombros',
  'chest': 'Pecho',
  'upper-back': 'Espalda alta',
  'serratus': 'Serrato',
  'biceps': 'Bíceps',
  'triceps': 'Tríceps',
  'forearm': 'Antebrazos',
  'abs': 'Abdominales',
  'obliques': 'Oblicuos',
  'lower-back': 'Espalda baja',
  'gluteal': 'Glúteos',
  'quadriceps': 'Cuádriceps',
  'hamstring': 'Isquiotibiales',
  'adductors': 'Aductores',
  'hip-flexors': 'Flexores de cadera',
  'calves': 'Gemelos',
  'tibialis': 'Tibiales',
};

/// A secondary muscle counts this much against a primary.
const secondaryWeight = 0.4;

/// Every `tg`/`sm` spelling in the dataset → muscle; null = not drawable.
const Map<String, String?> _alias = {
  'abs': 'abs', 'pectorals': 'chest', 'biceps': 'biceps', 'glutes': 'gluteal', 'delts': 'deltoids', //
  'triceps': 'triceps', 'upper back': 'upper-back', 'lats': 'upper-back', 'calves': 'calves',
  'quads': 'quadriceps', 'forearms': 'forearm', 'hamstrings': 'hamstring', 'spine': 'lower-back',
  'traps': 'trapezius', 'adductors': 'adductors', 'serratus anterior': 'serratus',
  'abductors': 'gluteal', 'levator scapulae': 'trapezius', 'cardiovascular system': null,
  'shoulders': 'deltoids', 'deltoids': 'deltoids', 'rear deltoids': 'deltoids',
  'rotator cuff': 'deltoids', 'quadriceps': 'quadriceps', 'core': 'abs', 'abdominals': 'abs',
  'lower abs': 'abs', 'chest': 'chest', 'upper chest': 'chest', 'hip flexors': 'hip-flexors',
  'obliques': 'obliques', 'lower back': 'lower-back', 'rhomboids': 'upper-back',
  'trapezius': 'trapezius', 'back': 'upper-back', 'latissimus dorsi': 'upper-back',
  'brachialis': 'biceps', 'soleus': 'calves', 'shins': 'tibialis', 'wrists': 'forearm',
  'wrist flexors': 'forearm', 'wrist extensors': 'forearm', 'grip muscles': 'forearm',
  'groin': 'adductors', 'inner thighs': 'adductors',
  'ankles': null, 'feet': null, 'hands': null, 'ankle stabilizers': null, 'sternocleidomastoid': null,
};

/// Custom exercises name no muscles: they spread over their body part (weights sum to 1).
const Map<String, Map<String, num>> _byBodyPart = {
  'chest': {'chest': 1},
  'back': {'upper-back': 0.75, 'lower-back': 0.25},
  'shoulders': {'deltoids': 1},
  'upper arms': {'biceps': 0.5, 'triceps': 0.5},
  'lower arms': {'forearm': 1},
  'waist': {'abs': 0.7, 'obliques': 0.3},
  'upper legs': {'quadriceps': 0.4, 'hamstring': 0.35, 'gluteal': 0.25},
  'lower legs': {'calves': 0.8, 'tibialis': 0.2},
  'neck': {'trapezius': 1},
  'cardio': {},
};

/// Muscle → load (effective sets).
typedef MuscleLoad = Map<String, num>;

/// Muscles one exercise trains, `{muscle: 0…1}`: the primary counts 1, each secondary 0.4 (never
/// downgrading a primary); nothing drawable falls back to the body part.
MuscleLoad musclesOf(ExerciseFacts? exercise) {
  if (exercise == null) return {};
  final out = <String, num>{};
  void add(String name, num weight) {
    final muscle = _alias[name.toLowerCase().trim()];
    if (muscle != null) out[muscle] = max(out[muscle] ?? 0, weight);
  }

  add(exercise.target, 1);
  for (final name in exercise.secondary) {
    add(name, secondaryWeight);
  }
  if (out.isEmpty) out.addAll(_byBodyPart[exercise.bodyPart] ?? const {});
  return out;
}

/// Effective sets per muscle; items with no sets or an unknown id add nothing.
MuscleLoad loadOf(ExerciseIndex catalog, Iterable<({String id, num sets})> items) {
  final load = <String, num>{};
  for (final (:id, :sets) in items) {
    if (sets == 0) continue;
    musclesOf(catalog.lookup(id)).forEach((muscle, weight) => load[muscle] = (load[muscle] ?? 0) + weight * sets);
  }
  return load;
}

/// Sets per muscle over finished workouts: done sets, optionally narrowed by [pick] (e.g.
/// `isHardSet` for "where the hard sets went").
MuscleLoad loadOfWorkouts(ExerciseIndex catalog, Iterable<Workout> workouts, {bool Function(SetRecord s)? pick}) =>
    loadOf(catalog, [
      for (final w in workouts)
        for (final e in w.entries) (id: e.id, sets: e.sets.where((s) => s.done && (pick == null || pick(s))).length),
    ]);

/// Planned sets per muscle for one routine (a missing `sets` counts as 1).
MuscleLoad loadOfRoutine(ExerciseIndex catalog, Routine? routine) => loadOf(catalog, [
  for (final c in routine?.ex ?? const <RoutineExercise>[]) (id: c.id, sets: c.sets == 0 ? 1 : c.sets),
]);

/// Done sets so far in the workout in progress.
MuscleLoad loadOfActive(ExerciseIndex catalog, ActiveWorkout? active) => loadOf(catalog, [
  for (final e in active?.entries ?? const <ActiveEntry>[]) (id: e.id, sets: e.sets.where((s) => s.done).length),
]);

/// Shade 0–4 per muscle (all 18), relative to the hardest-worked one; any load is at least 1.
Map<String, int> levelsOf(MuscleLoad load) {
  final top = muscles.fold<num>(0, (m, muscle) => max(m, load[muscle] ?? 0));
  int level(num v) => v == 0 || v.isNaN || top <= 0 ? 0 : max(1, min(4, (v / top * 4).ceil()));
  return {for (final muscle in muscles) muscle: level(load[muscle] ?? 0)};
}

/// Worked muscles by load (ties keep body order) and the untrained ones in body order.
({List<String> worked, List<String> missed}) rankOf(MuscleLoad load) {
  final worked = [
    for (final m in muscles)
      if ((load[m] ?? 0) > 0) m,
  ];
  // List.sort is not stable; sort indices so ties keep body order.
  final order = {for (var i = 0; i < worked.length; i++) worked[i]: i};
  worked.sort((a, b) {
    final byLoad = load[b]!.compareTo(load[a]!);
    return byLoad != 0 ? byLoad : order[a]!.compareTo(order[b]!);
  });
  return (
    worked: worked,
    missed: [
      for (final m in muscles)
        if (!((load[m] ?? 0) > 0)) m,
    ],
  );
}
