import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../shell.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../library/library_screen.dart';
import '../progress/workout_detail_sheet.dart';
import 'calendar_sheet.dart';
import 'day_sheets.dart';
import 'plan_tools_sheet.dart';
import 'plan_widgets.dart';
import 'routine_editing.dart';
import 'routine_editor_screen.dart';

export 'calendar_sheet.dart' show WorkoutDetailOpener, showCalendarSheet;
export 'day_sheets.dart' show showDayAssignSheet, showDayOverrideSheet;
export 'exercise_config_sheet.dart'
    show ExerciseConfigRemoved, ExerciseConfigResult, ExerciseConfigSaved, showExerciseConfigSheet;
export 'plan_tools_sheet.dart' show loadStarterPlanWithToast;
export 'routine_editor_screen.dart' show RoutineEditorScreen, openRoutineEditor;

/// The Plan tab (specs/ui.md §3.3): the week Monday to Sunday with each day's routine, the
/// routines, and the way into the exercise library, the calendar and the plan tools.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  static Future<void> _openLibrary(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LibraryScreen()));

  static void _newRoutine(BuildContext context) {
    final app = context.read<AppState>();
    late Routine created;
    app.updatePlan((plan) => plan.routines.add(created = newRoutine(plan, app.clock.now())));
    openRoutineEditor(context, created.id);
  }

  static Future<void> _openTools(BuildContext context) async {
    final tool = await showPlanToolsSheet(context);
    if (tool == null || !context.mounted) return;
    switch (tool) {
      case PlanTool.calendar:
        await showCalendarSheet(context, openWorkout: showWorkoutDetailSheet);
      case PlanTool.library:
        await _openLibrary(context);
      case PlanTool.starterPlan:
        loadStarterPlanWithToast(context);
      case PlanTool.coach:
        context.read<ShellController?>()?.goTo(AppTab.coach);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    return Scaffold(
      body: PageBody(
        children: [
          ScreenHeader(
            title: 'Plan',
            subtitle: 'Tu rutina semanal',
            leading: navigator.canPop()
                ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: navigator.pop)
                : null,
            actions: [
              AppIconButton(
                icon: 'calendar',
                tooltip: 'Calendario',
                onPressed: () => showCalendarSheet(context, openWorkout: showWorkoutDetailSheet),
              ),
              AppIconButton(icon: 'wrench', tooltip: 'Herramientas del plan', onPressed: () => _openTools(context)),
            ],
          ),
          const _WeekSchedule(),
          _RoutinesCaption(onNew: () => _newRoutine(context)),
          const _RoutineList(),
          _LibraryLink(onTap: () => _openLibrary(context)),
        ],
      ),
    );
  }
}

/// "Horario semanal": Monday to Sunday; each day shows its routine (accent tag) or "Descanso",
/// and opens the day assign sheet.
class _WeekSchedule extends StatelessWidget {
  const _WeekSchedule();

  static const _mondayFirst = [1, 2, 3, 4, 5, 6, 0];

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<AppState>().plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption('Horario semanal'),
        LayoutBuilder(
          // A long routine name is cut so the day name keeps its room.
          builder: (context, box) => ItemList(
            children: [
              for (final day in _mondayFirst)
                _WeekdayItem(
                  weekday: day,
                  routine: plan.routineById(plan.week['$day']),
                  tagMaxWidth: box.maxWidth * .55,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekdayItem extends StatelessWidget {
  const _WeekdayItem({required this.weekday, required this.routine, required this.tagMaxWidth});

  /// 0 = Sunday.
  final int weekday;
  final Routine? routine;
  final double tagMaxWidth;

  @override
  Widget build(BuildContext context) {
    final r = routine;
    return ListItem(
      title: dayNames[weekday],
      trailing: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tagMaxWidth),
          child: r == null ? const Tag('Descanso') : RoutineTag(name: r.name, emoji: r.emoji),
        ),
        const Chevron(),
      ],
      onTap: () => showDayAssignSheet(context, weekday),
    );
  }
}

/// "Rutinas" with the small "Nueva" button.
class _RoutinesCaption extends StatelessWidget {
  const _RoutinesCaption({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
    child: Row(
      children: [
        Expanded(child: Text('Rutinas', style: context.textStyles.caption)),
        AppButton('Nueva', icon: 'plus', size: ButtonSize.sm, variant: ButtonVariant.tinted, onPressed: onNew),
      ],
    ),
  );
}

/// The routines in plan order, each opening the editor; without routines, the way to the
/// starter plan.
class _RoutineList extends StatelessWidget {
  const _RoutineList();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final routines = app.plan.routines;
    if (routines.isEmpty) {
      return EmptyState(
        icon: 'clipboard',
        message: 'Aún no hay rutinas.\nCrea una o carga el plan inicial (Empuje / Tirón / Pierna).',
        action: AppButton('Cargar plan inicial', icon: 'sparkles', onPressed: () => loadStarterPlanWithToast(context)),
      );
    }
    return ItemList(
      children: [
        for (final r in routines)
          ListItem(
            leading: IconBadge.routine(r.emoji),
            title: r.name,
            subtitle: _summary(app, r),
            trailing: const [Chevron()],
            onTap: () => openRoutineEditor(context, r.id),
          ),
      ],
    );
  }

  /// "6 ejercicios · Barbell Bench Press, Barbell Incline Bench Press, …" (cut at two lines).
  static String _summary(AppState app, Routine r) {
    if (r.ex.isEmpty) return exCount(0);
    final names = [for (final e in r.ex) capitalizeWords(app.catalog.exOr(e.id).name)];
    return '${exCount(r.ex.length)} · ${names.join(', ')}';
  }
}

/// The exercise library, reached from here since the port has no Exercises tab.
class _LibraryLink extends StatelessWidget {
  const _LibraryLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = context.select<AppState, int>((s) => s.catalog.length);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Section(
        title: 'Ejercicios',
        children: [
          ListRow(
            icon: 'magnifier',
            title: 'Biblioteca de ejercicios',
            subtitle: '$count ejercicios · crea los tuyos',
            accessory: RowAccessory.chevron,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}
