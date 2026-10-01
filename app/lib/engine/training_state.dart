import '../data/models/body_weight.dart';
import '../data/models/workout.dart';
import 'catalog.dart';

/// The part of the original state `S` the progression engine reads: the exercise index, the
/// finished workouts **in `(d, start)` order** (engine-Q6; see `sortWorkouts`), the profile unit
/// and the working weights.
class TrainingState {
  const TrainingState({required this.catalog, required this.workouts, this.unit = 'kg', this.exWeights = const {}});

  final ExerciseIndex catalog;
  final List<Workout> workouts;

  /// `'kg'` or `'lb'`; anything but `'lb'` counts as kg.
  final String unit;

  /// `exWeights[exId]`: the confirmed working weight (a running max).
  final Map<String, ExWeight> exWeights;
}
