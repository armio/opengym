import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/clock.dart';
import '../../../data/library.dart';
import '../../../data/models/models.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';

/// Called after "Nueva rutina" created a routine with the exercise in it (the original then
/// opens the routine editor).
typedef RoutineCreatedCallback = void Function(Routine routine);

/// Name of a routine created from the library.
const newRoutineName = 'Nueva rutina';

/// `defaultConfig(id)` for a freshly added exercise: cardio `{sets 1, min 20, speed 8}`,
/// everything else `{sets 3, reps 10, weight 0, mode 'reps'}` — the owner switches an exercise
/// to timed sets in the routine editor.
RoutineExercise defaultRoutineExercise(Exercise exercise) => exercise.isCardio
    ? RoutineExercise(id: exercise.id, sets: 1, min: 20, speed: 8)
    : RoutineExercise(id: exercise.id, sets: 3, reps: 10, weight: 0, mode: 'reps');

/// "Añadir «…»" (specs/ui.md §4.6): lists the routines (with "ya incluido" when the exercise is
/// already there — duplicates are allowed) and "Nueva rutina". Picking one appends the
/// exercise's default config to that routine, toasts "«…» añadido a …" and, for a new routine,
/// calls [onRoutineCreated].
Future<void> showAddToRoutineSheet(
  BuildContext context,
  Exercise exercise, {
  RoutineCreatedCallback? onRoutineCreated,
}) async {
  final choice = await showAppSheet<_RoutineChoice>(
    context,
    title: 'Añadir «${capitalizeWords(exercise.name)}»',
    builder: (_) => _AddToRoutine(exercise: exercise),
  );
  if (choice == null || !context.mounted) return;

  final app = context.read<AppState>();
  final routine = switch (choice) {
    _NewRoutine() => Routine(id: uid(app.clock), name: newRoutineName, emoji: defaultGlyph),
    _ExistingRoutine(:final routineId) => app.plan.routineById(routineId),
  };
  if (routine == null) return;
  final isNew = choice is _NewRoutine;
  app.updatePlan((plan) {
    if (isNew) plan.routines.add(routine.copy());
    plan.routineById(routine.id)?.ex.add(defaultRoutineExercise(exercise));
  });
  showToast(context, '«${capitalizeWords(exercise.name)}» añadido a ${routine.name}');
  if (isNew) onRoutineCreated?.call(app.plan.routineById(routine.id) ?? routine);
}

sealed class _RoutineChoice {
  const _RoutineChoice();
}

class _NewRoutine extends _RoutineChoice {
  const _NewRoutine();
}

class _ExistingRoutine extends _RoutineChoice {
  const _ExistingRoutine(this.routineId);

  final String routineId;
}

class _AddToRoutine extends StatelessWidget {
  const _AddToRoutine({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final routines = context.select<AppState, List<Routine>>((s) => s.plan.routines);
    final p = context.palette;
    void pick(_RoutineChoice choice) => Navigator.of(context).pop(choice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Elige una rutina — series, repeticiones y peso los ajustas después en la rutina.',
          style: context.textStyles.small,
        ),
        const SizedBox(height: 12),
        ItemList(
          children: [
            for (final r in routines)
              ListItem(
                leading: IconBadge.routine(r.emoji),
                title: r.name,
                subtitle: exerciseCount(r.ex.length),
                trailing: [
                  if (r.ex.any((e) => e.id == exercise.id)) const Tag('ya incluido', capitalize: false),
                  AppIcon('plus', size: 18, color: p.label3),
                ],
                onTap: () => pick(_ExistingRoutine(r.id)),
              ),
            ListItem(
              leading: IconBadge(icon: 'sparkles', tint: p.surface3, foreground: p.label),
              title: newRoutineName,
              subtitle: 'Crea una y empieza con este ejercicio',
              trailing: [AppIcon('plus', size: 18, color: p.label3)],
              onTap: () => pick(const _NewRoutine()),
            ),
          ],
        ),
      ],
    );
  }
}

/// `exCount(n)`: "1 ejercicio" / "N ejercicios".
String exerciseCount(int n) => n == 1 ? '1 ejercicio' : '$n ejercicios';
