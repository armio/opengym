/// The exercise facts the engine reads, behind an interface so the engine stays pure Dart:
/// the app adapts its `ExerciseCatalog` (see `catalog_bridge.dart`), tests pass a map.
library;

import '../data/models/plan.dart';

/// What the engine needs to know about one exercise.
abstract interface class ExerciseFacts {
  /// English, lowercase (the dataset has no translated names).
  String get name;

  /// Decides the logging mode (`cardio`), the default increment and the muscle fallback.
  String get bodyPart;

  /// Primary target muscle (free text; empty for custom exercises).
  String get target;

  /// Secondary muscles (free text).
  List<String> get secondary;
}

/// A plain [ExerciseFacts] value.
class ExerciseInfo implements ExerciseFacts {
  const ExerciseInfo({required this.name, required this.bodyPart, this.target = '', this.secondary = const []});

  /// A custom exercise of the plan doc: no target, no secondary muscles.
  ExerciseInfo.custom(CustomExercise c) : this(name: c.n, bodyPart: c.bp, target: c.tg);

  @override
  final String name;
  @override
  final String bodyPart;
  @override
  final String target;
  @override
  final List<String> secondary;
}

/// Looks exercises up by id: the library plus the owner's custom exercises.
abstract class ExerciseIndex {
  const ExerciseIndex();

  /// The exercise with [id], or null when unknown.
  ExerciseFacts? lookup(String id);

  /// `isCardio(id)`: the body part is `cardio`. Unknown ids are not cardio.
  bool isCardio(String? id) => id != null && lookup(id)?.bodyPart == 'cardio';

  /// The exercise's name, or "Ejercicio desconocido" (`exName`).
  String nameOf(String? id) => (id == null ? null : lookup(id)?.name) ?? unknownExerciseName;

  /// This index with [customs] looked up first — e.g. the custom exercises of a draft plan that
  /// the app's catalogue does not know yet.
  ExerciseIndex withCustoms(List<CustomExercise> customs) => customs.isEmpty ? this : _WithCustoms(this, customs);
}

/// Shown for an id that resolves nowhere.
const unknownExerciseName = 'Ejercicio desconocido';

/// An index over a fixed map (tests, small catalogues).
class MapExerciseIndex extends ExerciseIndex {
  const MapExerciseIndex(this.exercises);

  final Map<String, ExerciseFacts> exercises;

  @override
  ExerciseFacts? lookup(String id) => exercises[id];
}

class _WithCustoms extends ExerciseIndex {
  _WithCustoms(this.base, List<CustomExercise> customs)
    : customs = {for (final c in customs) c.id: ExerciseInfo.custom(c)};

  final ExerciseIndex base;
  final Map<String, ExerciseFacts> customs;

  @override
  ExerciseFacts? lookup(String id) => customs[id] ?? base.lookup(id);
}
