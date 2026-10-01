import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../library/library_screen.dart' show createCustomExercise;
import 'exercise_config_sheet.dart';
import 'glyph_picker_sheet.dart';
import 'plan_widgets.dart';
import 'routine_editing.dart';
import 'routine_exercise_list.dart';

/// Opens the routine editor for [routineId] on the current navigator.
Future<void> openRoutineEditor(BuildContext context, String routineId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutineEditorScreen(routineId: routineId)));

/// The routine editor (specs/ui.md §3.4): name (saved on every keystroke), icon, routine-level
/// progression, the exercise list with reorder and superset links, what the session hits on
/// the body map, add exercises (the picker stays open for several) and delete the routine.
/// Leaves by itself when the routine stops existing.
class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({super.key, required this.routineId});

  final String routineId;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  bool _leaving = false;

  AppState get _app => context.read<AppState>();

  Routine? get _routine => _app.plan.routineById(widget.routineId);

  /// One `plan` edit of this routine (skipped if it was deleted meanwhile).
  void _edit(void Function(PlanDoc plan, Routine routine) fn) => _app.updatePlan((plan) {
    final routine = plan.routineById(widget.routineId);
    if (routine != null) fn(plan, routine);
  });

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).maybePop();
  }

  void _toggleLink(int i) {
    final now = _app.clock.now();
    _edit((plan, r) => toggleSupersetLink(r.ex, i, () => newSupersetTag(plan, now)));
  }

  void _move(int i, int dir) => _edit((_, r) => moveRoutineExercise(r.ex, i, dir));

  Future<void> _pickGlyph(Routine routine) async {
    final glyph = await showGlyphPicker(context, routine.emoji);
    if (glyph != null && mounted) _edit((_, r) => r.emoji = glyph);
  }

  Future<void> _openExercise(int i) async {
    final routine = _routine;
    if (routine == null || i >= routine.ex.length) return;
    final entry = routine.ex[i];
    final result = await showExerciseConfigSheet(
      context,
      exercise: _app.catalog.exOr(entry.id),
      existing: entry,
      routine: routine,
      allowDelete: true,
    );
    if (result == null || !mounted) return;
    _edit((_, r) {
      // The list may have changed under the sheet (e.g. a sync): only touch the same entry.
      if (i >= r.ex.length || r.ex[i].id != entry.id) return;
      switch (result) {
        case ExerciseConfigSaved(:final config):
          replaceRoutineExercise(r.ex, i, config);
        case ExerciseConfigRemoved():
          removeRoutineExercise(r.ex, i);
      }
    });
  }

  /// The picker stays open: every pick opens the config sheet on top, and saving appends.
  Future<void> _addExercises() => showExercisePicker(
    context,
    onCreateCustom: createCustomExercise,
    onPick: (exercise) async {
      final result = await showExerciseConfigSheet(context, exercise: exercise, routine: _routine);
      if (result is ExerciseConfigSaved && mounted) {
        _edit((_, r) => r.ex.add(result.config.copy()));
      }
    },
  );

  Future<void> _delete(Routine routine) async {
    final confirmed = await showConfirm(
      context,
      title: '¿Eliminar rutina?',
      message: '«${routine.name}» y sus ejercicios se eliminarán.',
      confirmText: 'Eliminar',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    _app.deleteRoutine(routine.id);
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final routine = context.watch<AppState>().plan.routineById(widget.routineId);
    if (routine == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _leave();
      });
      return const Scaffold();
    }
    return Scaffold(
      body: PageBody(
        children: [
          _EditorHeader(
            key: ValueKey(widget.routineId),
            routine: routine,
            onBack: _leave,
            onRename: (text) => _edit((_, r) => r.name = routineNameFor(text)),
            onPickGlyph: () => _pickGlyph(routine),
          ),
          _RoutineProgression(routine: routine, onChanged: (policy) => _edit((_, r) => r.prog = policy)),
          if (routine.ex.isEmpty)
            const EmptyState(icon: 'dumbbell', message: 'Aún no hay ejercicios — añade el primero.')
          else ...[
            RoutineExerciseList(routine: routine, onOpen: _openExercise, onToggleLink: _toggleLink, onMove: _move),
            const SizedBox(height: 12),
            RoutineCoverageCard(routine: routine),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 10, 2, 10),
            child: DimNote(
              'Toca el botón de enlace en un ejercicio para hacer superserie con el de arriba — los harás seguidos.',
              icon: 'link',
            ),
          ),
          AppButton('Añadir ejercicio', icon: 'plus', variant: ButtonVariant.primary, onPressed: _addExercises),
          const SizedBox(height: 10),
          AppButton('Eliminar rutina', variant: ButtonVariant.danger, onPressed: () => _delete(routine)),
        ],
      ),
    );
  }
}

/// Back button, the name field and the icon button. The field is seeded once with the name
/// and not updated from outside afterwards; every keystroke stores the trimmed text, or
/// "Rutina" while it is empty (the field then stays empty — specs/ui.md §11.1).
class _EditorHeader extends StatefulWidget {
  const _EditorHeader({
    super.key,
    required this.routine,
    required this.onBack,
    required this.onRename,
    required this.onPickGlyph,
  });

  final Routine routine;
  final VoidCallback onBack;
  final ValueChanged<String> onRename;
  final VoidCallback onPickGlyph;

  @override
  State<_EditorHeader> createState() => _EditorHeaderState();
}

class _EditorHeaderState extends State<_EditorHeader> {
  late final _name = TextEditingController(text: widget.routine.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 18),
    child: Row(
      children: [
        AppIconButton(icon: 'chevronLeft', tooltip: 'Plan', onPressed: widget.onBack),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _name,
            onChanged: widget.onRename,
            style: context.textStyles.sheetTitle,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: fallbackRoutineName),
          ),
        ),
        const SizedBox(width: 12),
        AppIconButton(icon: glyphOf(widget.routine.emoji), tooltip: 'Elige un icono', onPressed: widget.onPickGlyph),
      ],
    ),
  );
}

/// "Progresión": the routine-wide rule (reps policies only; unset reads as linear) and what it
/// applies to.
class _RoutineProgression extends StatelessWidget {
  const _RoutineProgression({required this.routine, required this.onChanged});

  final Routine routine;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = routine.prog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupedBox(
          child: SelectRow<String>(
            icon: 'chartLine',
            title: 'Progresión',
            sheetTitle: 'Progresión',
            value: current == null || current.isEmpty ? 'linear' : current,
            options: [
              for (final policy in policiesFor[ExerciseMode.reps]!)
                SelectOption(policy, policyNames[policy]!, subtitle: policyDescriptions[policy]),
            ],
            onChanged: onChanged,
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 6, 2, 16),
          child: DimNote('Se aplica a cada ejercicio de esta rutina que no defina su propia regla.'),
        ),
      ],
    );
  }
}
