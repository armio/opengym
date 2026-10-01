import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import 'active_workout_view.dart';
import 'start_chooser.dart';

export 'services/rest_alerts.dart' show LocalRestAlerts, NoRestAlerts, RestAlerts;
export 'services/screen_wake_lock.dart' show PlatformWakeLock, ScreenWakeLock;
export 'services/workout_feedback.dart' show WorkoutFeedback;
export 'services/workout_timers.dart' show Countdown, HoldTarget, WorkoutTimers;
export 'elapsed_text.dart';
export 'workout_controller.dart';

/// The full-screen workout route (specs/ui.md §3.5, §5): the workout in progress, or the start
/// chooser when there is none.
class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key});

  /// The route name the launcher pushes it under.
  static const routeName = '/workout';

  @override
  Widget build(BuildContext context) {
    final active = context.select<AppState, bool>((s) => s.active != null);
    return active ? const ActiveWorkoutView() : const StartChooser();
  }
}
