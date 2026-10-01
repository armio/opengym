/// Glue between the app's data layer and the engine. This is the one engine file that imports
/// Flutter code (the catalogue and AppState live there); everything else is pure Dart.
library;

import '../data/app_state.dart';
import '../data/library.dart';
import 'catalog.dart';
import 'training_state.dart';

/// The app's [ExerciseCatalog] (library + custom exercises) as the engine's [ExerciseIndex].
class CatalogExerciseIndex extends ExerciseIndex {
  const CatalogExerciseIndex(this.catalog);

  final ExerciseCatalog catalog;

  @override
  ExerciseFacts? lookup(String id) {
    final e = catalog.byId(id);
    return e == null ? null : _ExerciseView(e);
  }
}

class _ExerciseView implements ExerciseFacts {
  const _ExerciseView(this.e);

  final Exercise e;

  @override
  String get name => e.name;
  @override
  String get bodyPart => e.bodyPart;
  @override
  String get target => e.target;
  @override
  List<String> get secondary => e.secondary;
}

/// Engine views of the live app data.
extension AppStateEngine on AppState {
  /// The exercise index over the current catalogue (library + the plan's custom exercises).
  ExerciseIndex get exerciseIndex => CatalogExerciseIndex(catalog);

  /// Everything the progression engine reads: catalogue, workouts in `(d, start)` order, unit and
  /// working weights.
  TrainingState get trainingState =>
      TrainingState(catalog: exerciseIndex, workouts: workouts, unit: settings.unit, exWeights: exWeights);
}
