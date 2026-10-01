/// The workout's multi-step flows (specs/ui.md §5.4, §5.10–§5.12): discard, add an exercise,
/// the "whole workout" dialog and finishing with its summary.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../library/library_screen.dart' show createCustomExercise;
import '../plan/plan_screen.dart' show ExerciseConfigSaved, showExerciseConfigSheet;
import 'finish_summary_sheet.dart';
import 'workout_screen.dart';

/// Pops the workout screen (back to the tabs), if it is a pushed route.
void closeWorkoutScreen(NavigatorState navigator) {
  if (!navigator.mounted) return;
  navigator.popUntil((route) => route.settings.name != WorkoutScreen.routeName);
}

/// "Descartar" (✕): confirm, throw the session away and leave the workout screen.
Future<void> discardWorkout(BuildContext context) async {
  final confirmed = await showConfirm(
    context,
    title: '¿Descartar entrenamiento?',
    message: 'Las series registradas en esta sesión se perderán.',
    confirmText: 'Descartar',
    danger: true,
  );
  if (!confirmed || !context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  await context.read<WorkoutController>().discard();
  closeWorkoutScreen(navigator);
}

/// "Añadir ejercicio": the picker stays open (several can be added); each pick opens the config
/// sheet on top, with the session's routine for the inherited progression, and saving appends
/// the entry and jumps to it.
Future<void> addExerciseToWorkout(BuildContext context) async {
  final controller = context.read<WorkoutController>();
  await showExercisePicker(
    context,
    onCreateCustom: createCustomExercise,
    onPick: (exercise) async {
      final result = await showExerciseConfigSheet(
        context,
        exercise: exercise,
        routine: controller.sessionRoutine,
        saveLabel: 'Añadir al entrenamiento',
      );
      if (result is ExerciseConfigSaved) controller.addExercise(result.config);
    },
  );
}

/// "¡Ese era todo el entrenamiento!": finish, or keep going.
Future<void> showWorkoutCompleteDialog(BuildContext context) async {
  final finish = await showAppDialog<bool>(context, builder: (ctx) => const _WorkoutCompleteDialog());
  if (!context.mounted) return;
  if (finish == true) {
    await finishWorkoutFlow(context);
  } else if (finish == false) {
    showToast(context, 'Sigue así — toca «+ Añadir ejercicio» abajo');
  }
}

class _WorkoutCompleteDialog extends StatelessWidget {
  const _WorkoutCompleteDialog();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(child: AppIcon('checkCircle', size: 44, color: p.acc)),
        const SizedBox(height: 8),
        Text("¡Ese era todo el entrenamiento!", textAlign: TextAlign.center, style: t.sheetTitle),
        const SizedBox(height: 8),
        Text(
          'Todos los ejercicios hechos — ¡buen trabajo! Termina, o sigue y añade otro ejercicio.',
          textAlign: TextAlign.center,
          style: t.small,
        ),
        const SizedBox(height: 16),
        AppButton(
          'Terminar entrenamiento',
          icon: 'flag',
          variant: ButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 8),
        AppButton('Continuar entrenamiento', onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}

/// "Terminar" (specs/ui.md §5.11): asks first when nothing or not everything is checked, then
/// stores the workout, shows the summary (locked: only "¡Genial!" closes it) and leaves the
/// workout screen.
Future<void> finishWorkoutFlow(BuildContext context) async {
  final controller = context.read<WorkoutController>();
  final active = controller.active;
  if (active == null) return;
  final done = setsDoneActive(active), total = setsTotalActive(active);
  if (done == 0) {
    final ok = await showConfirm(
      context,
      title: 'Nada registrado aún',
      message: 'No has marcado ninguna serie. ¿Terminar el entrenamiento igualmente?',
      confirmText: 'Terminar igualmente',
    );
    if (!ok) return;
  } else if (done < total) {
    final left = total - done;
    final ok = await showConfirm(
      context,
      title: '¿Terminar antes?',
      message: left == 1
          ? 'Queda 1 serie sin marcar. ¿Terminar ahora?'
          : 'Quedan $left series sin marcar. ¿Terminar ahora?',
      confirmText: 'Terminar entrenamiento',
    );
    if (!ok) return;
  }
  if (!context.mounted) return;
  // The screen below turns into the start chooser as soon as the workout is stored, so the
  // summary is shown from the navigator.
  final navigator = Navigator.of(context, rootNavigator: true);
  final summary = await controller.finish();
  if (summary == null || !navigator.mounted) return;
  await showFinishSummary(navigator.context, summary);
  closeWorkoutScreen(navigator);
}
