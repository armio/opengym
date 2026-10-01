import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/library.dart';
import '../../../data/models/models.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'add_to_routine_sheet.dart';
import 'custom_exercise_sheet.dart';
import 'exercise_records.dart';

/// The exercise detail sheet (specs/ui.md §4.5): animation with its attribution, Spanish
/// taxonomy tags, the custom description, the best load and last session, "Añadir a rutina",
/// edit/delete for custom exercises, the estimated-1RM calculator (not for cardio) and the
/// numbered instructions in Spanish with an English toggle.
///
/// When "Añadir a rutina" creates a routine, the detail closes and [onRoutineCreated] runs (it
/// usually navigates to the new routine).
Future<void> showExerciseDetailSheet(
  BuildContext context,
  Exercise exercise, {
  RoutineCreatedCallback? onRoutineCreated,
}) async {
  final action = await showAppSheet<_DetailAction>(
    context,
    builder: (_) => _ExerciseDetail(exercise: exercise, closeOnNewRoutine: onRoutineCreated != null),
  );
  if (!context.mounted) return;
  switch (action) {
    // "Editar" closes the detail first (as in the original), so the form opens from the caller.
    case _EditCustom():
      final current = context.read<AppState>().catalog.byId(exercise.id);
      if (current != null) await showCustomExerciseSheet(context, existing: current);
    case _RoutineCreated(:final routine):
      onRoutineCreated?.call(routine);
    case null:
      break;
  }
}

/// Why the detail sheet closed, when the caller has something left to do.
sealed class _DetailAction {
  const _DetailAction();
}

class _EditCustom extends _DetailAction {
  const _EditCustom();
}

class _RoutineCreated extends _DetailAction {
  const _RoutineCreated(this.routine);

  final Routine routine;
}

class _ExerciseDetail extends StatelessWidget {
  const _ExerciseDetail({required this.exercise, required this.closeOnNewRoutine});

  final Exercise exercise;
  final bool closeOnNewRoutine;

  Future<void> _delete(BuildContext context, Exercise ex) async {
    final deleted = await confirmDeleteCustomExercise(context, ex);
    if (deleted && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // The live record: a custom exercise may have been renamed meanwhile.
    final ex = app.catalog.byId(exercise.id) ?? exercise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(capitalizeWords(ex.name)),
        ExerciseMedia(exercise: ex),
        const SizedBox(height: 10),
        _TaxonomyTags(exercise: ex),
        const SizedBox(height: 10),
        if (ex.desc.isNotEmpty) _DescriptionBox(ex.desc),
        _BestLoad(exercise: ex),
        const SizedBox(height: 10),
        AppButton(
          'Añadir a rutina',
          icon: 'plus',
          variant: ButtonVariant.primary,
          onPressed: () => showAddToRoutineSheet(
            context,
            ex,
            onRoutineCreated: closeOnNewRoutine
                ? (routine) {
                    if (context.mounted) Navigator.of(context).pop(_RoutineCreated(routine));
                  }
                : null,
          ),
        ),
        if (ex.custom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  'Editar',
                  icon: 'pencil',
                  onPressed: () => Navigator.of(context).pop(const _EditCustom()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  'Eliminar',
                  icon: 'trash',
                  variant: ButtonVariant.danger,
                  onPressed: () => _delete(context, ex),
                ),
              ),
            ],
          ),
        ],
        if (!ex.isCardio) _OneRepMaxCalculator(exercise: ex, key: ValueKey('1rm-${ex.id}')),
        if (ex.steps.isNotEmpty) _Instructions(exercise: ex),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _TaxonomyTags extends StatelessWidget {
  const _TaxonomyTags({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final ex = exercise;
    final secondary = ex.secondaryEs.isNotEmpty ? ex.secondaryEs : ex.secondary.map(muscleLabel).toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (ex.bodyPartEs.isNotEmpty) Tag(ex.bodyPartEs, accent: true),
        if (ex.targetEs.isNotEmpty) Tag(ex.targetEs, icon: 'target'),
        if (ex.equipmentEs.isNotEmpty) Tag(ex.equipmentEs, icon: 'dumbbell'),
        for (final muscle in secondary.take(3)) Tag(muscle),
      ],
    );
  }
}

/// A custom exercise's description (`.exnote`).
class _DescriptionBox extends StatelessWidget {
  const _DescriptionBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(AppRadii.r)),
      child: Text(text, style: TextStyle(fontSize: 15, height: 1.45, color: p.label2)),
    );
  }
}

/// "Mejor: 80 kg · último 28 sept: 80×5, 80×5" — shown once there is a best load.
class _BestLoad extends StatelessWidget {
  const _BestLoad({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final best = bestWeights(app.workouts, isCardio: app.catalog.isCardio)[exercise.id] ?? 0;
    if (best <= 0) return const SizedBox.shrink();
    final p = context.palette;
    final t = context.textStyles;
    final last = lastSessionFor(app.workouts, exercise.id);
    final lastText = last == null
        ? ''
        : ' · último ${formatDate(last.d)}: '
              '${last.sets.map((s) => setLabel(s, modeOf(last.mode, cardio: exercise.isCardio))).join(', ')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon('trophy', size: 14, color: p.yellow),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: t.small.copyWith(color: p.label),
                children: [
                  const TextSpan(text: 'Mejor: '),
                  TextSpan(
                    text: formatWeight(best, app.settings.unit),
                    style: TextStyle(color: p.acc, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: lastText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "1RM estimado" (issue #18): the best estimate from the log plus an Epley calculator seeded
/// from it (else from the working weight, else 20 × 5).
class _OneRepMaxCalculator extends StatefulWidget {
  const _OneRepMaxCalculator({super.key, required this.exercise});

  final Exercise exercise;

  @override
  State<_OneRepMaxCalculator> createState() => _OneRepMaxCalculatorState();
}

class _OneRepMaxCalculatorState extends State<_OneRepMaxCalculator> {
  late num? _weight;
  late num? _reps;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final best = bestOneRepMax(app.workouts, widget.exercise.id);
    _weight = best?.w ?? app.exWeights[widget.exercise.id]?.w ?? 20;
    _reps = best?.r ?? 5;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final unit = app.settings.unit;
    final best = bestOneRepMax(app.workouts, widget.exercise.id);
    final estimate = estimateOneRepMax(_weight, _reps);
    final p = context.palette;
    final t = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionCaption('1RM estimado'),
        if (best != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                style: t.small.copyWith(color: p.label),
                children: [
                  const TextSpan(text: 'De tu registro: '),
                  TextSpan(
                    text: formatWeight(best.est, unit),
                    style: TextStyle(color: p.acc, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' · ${formatWeight(best.w, unit)} × ${best.r} el ${formatDate(best.d)}',
                    style: TextStyle(color: p.label3),
                  ),
                ],
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: ValueStepper(
                label: 'Peso ($unit)',
                value: _weight,
                step: 2.5,
                onChanged: (v) => setState(() => _weight = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ValueStepper(
                label: 'Reps',
                value: _reps,
                decimal: false,
                onChanged: (v) => setState(() => _reps = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Text('Estimación', style: t.small)),
            Text(
              estimate == null ? '—' : formatWeight(estimate, unit),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.acc),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          estimate == null
              ? 'Introduce un peso y 1–$oneRepMaxRepCap repeticiones: más allá, la estimación es adivinar.'
              : 'Fórmula de Epley: un cálculo a partir de una serie, no un máximo probado.',
          style: t.small.copyWith(color: p.label3),
        ),
      ],
    );
  }
}

/// "Cómo hacerlo": the numbered steps, in Spanish with an ES/EN switch when both exist.
class _Instructions extends StatefulWidget {
  const _Instructions({required this.exercise});

  final Exercise exercise;

  @override
  State<_Instructions> createState() => _InstructionsState();
}

class _InstructionsState extends State<_Instructions> {
  bool _english = false;

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    final hasSpanish = ex.instructionsEs.isNotEmpty;
    final canToggle = hasSpanish && ex.instructions.isNotEmpty;
    final english = !hasSpanish || (_english && canToggle);
    final steps = english ? ex.instructions : ex.instructionsEs;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionCaption(
          hasSpanish ? 'Cómo hacerlo' : 'Cómo hacerlo · instrucciones en inglés',
          trailing: canToggle
              ? Segmented<bool>(
                  inline: true,
                  segments: const [Segment(false, 'Español'), Segment(true, 'English')],
                  value: _english,
                  onChanged: (v) => setState(() => _english = v),
                )
              : null,
        ),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 2 : 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text('${i + 1}.', style: TextStyle(fontSize: 15, height: 1.5, color: p.label3)),
                ),
                Expanded(
                  child: Text(steps[i], style: TextStyle(fontSize: 15, height: 1.5, color: p.label2)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
