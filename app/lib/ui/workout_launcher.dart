import 'package:flutter/material.dart';

import 'screens/workout/workout_screen.dart';

/// What the tab bar's centre "Entrenar" button does. Provided at the root
/// (`Provider<WorkoutLauncher>` in `app.dart`) so the workout track can supply the real flow
/// (contract §6): an active workout → resume it; today's effective routine with at least one
/// exercise → body-weight check-in, then start it; otherwise → the "Empezar entreno" chooser.
abstract class WorkoutLauncher {
  const WorkoutLauncher();

  Future<void> launch(BuildContext context);
}

/// Opens [WorkoutScreen] full screen (over the tab bar); the workout track's screen decides
/// between resuming and the start chooser.
class DefaultWorkoutLauncher extends WorkoutLauncher {
  const DefaultWorkoutLauncher();

  @override
  Future<void> launch(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const WorkoutScreen()));
}
