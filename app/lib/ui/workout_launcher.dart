import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../engine/engine.dart';
import 'screens/workout/workout_screen.dart';
import 'widgets/widgets.dart';

/// How workouts start (contract §6 Navigation). Provided at the root
/// (`Provider<WorkoutLauncher>` in `app.dart`); the tab bar's "Entrenar" button calls [launch],
/// Home and the start chooser call [startRoutine] and [openWorkout].
abstract class WorkoutLauncher {
  const WorkoutLauncher();

  /// "Entrenar": an active workout → resume it; today's effective routine with at least one
  /// exercise → body-weight check-in, then start it; otherwise → the "Empezar entrenamiento"
  /// chooser.
  Future<void> launch(BuildContext context);

  /// `startFlow`: the locked body-weight check-in, then the session of [routineId] (null =
  /// freestyle). "Elegir otro entrenamiento" opens the chooser instead.
  Future<void> startRoutine(BuildContext context, String? routineId);

  /// Shows the workout screen (the active workout, or the chooser) full screen, unless
  /// [context] is already on it.
  Future<void> openWorkout(BuildContext context);
}

/// The app's launcher.
class DefaultWorkoutLauncher extends WorkoutLauncher {
  const DefaultWorkoutLauncher();

  @override
  Future<void> launch(BuildContext context) async {
    final app = context.read<AppState>();
    if (app.active == null) {
      final today = effectiveRoutine(app.plan, app.schedule, app.clock.todayIso());
      if (today != null && today.ex.isNotEmpty) return startRoutine(context, today.id);
    }
    return openWorkout(context);
  }

  @override
  Future<void> startRoutine(BuildContext context, String? routineId) async {
    final app = context.read<AppState>();
    if (app.active != null) return openWorkout(context);
    final checkIn = await showCheckInSheet(context);
    if (!context.mounted) return;
    if (!checkIn.start) return openWorkout(context);
    await context.read<WorkoutController>().begin(app.plan.routineById(routineId), bodyWeight: checkIn.bodyWeight);
    if (context.mounted) await openWorkout(context);
  }

  @override
  Future<void> openWorkout(BuildContext context) async {
    if (ModalRoute.of(context)?.settings.name == WorkoutScreen.routeName) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: WorkoutScreen.routeName),
        builder: (_) => const WorkoutScreen(),
      ),
    );
  }
}
