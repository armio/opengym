import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/library.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../library/library_screen.dart' show showExerciseDetailSheet;
import 'set_table.dart';

/// One exercise of the session (`ExerciseBlock`, specs/ui.md §5.5): animation, name with the
/// detail button, tags with the best load, "last time", the prescription's reason, and the set
/// table. [compact] is the superset-card variant.
class ExerciseBlock extends StatelessWidget {
  const ExerciseBlock({super.key, required this.entryIndex, this.compact = false});

  final int entryIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final entry = app.active!.entries[entryIndex];
    final exercise = app.catalog.exOr(entry.id);
    final mode = targetModeOf(app.exerciseIndex, entry.target, entry.id);
    final unit = app.settings.unit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (exercise.hasMedia) ...[
          ExerciseMedia(
            key: ValueKey('media-${entry.id}'),
            exercise: exercise,
            size: compact ? MediaSize.compact : MediaSize.full,
            minimizable: true,
          ),
          const SizedBox(height: 12),
        ],
        _TitleRow(exercise: exercise, compact: compact),
        _Tags(exercise: exercise, cardio: mode == ExerciseMode.cardio, best: previousBest(app.trainingState, entry)),
        _LastTime(entry: entry),
        _ProgressionLine(plan: entry.plan),
        const SizedBox(height: 10),
        SetTable(
          entryIndex: entryIndex,
          entry: entry,
          timed: mode == ExerciseMode.time,
          columns: setColumnsFor(mode, unit: unit, effortScale: app.settings.effortScale),
        ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.exercise, required this.compact});

  final Exercise exercise;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            capitalizeWords(exercise.name),
            style: TextStyle(
              fontSize: compact ? 17 : 20,
              fontWeight: FontWeight.w600,
              letterSpacing: (compact ? 17 : 20) * -.02,
              height: 1.2,
              color: context.palette.label,
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppIconButton(
          icon: 'info',
          tooltip: 'Detalles',
          onPressed: exercise.missing ? null : () => showExerciseDetailSheet(context, exercise),
        ),
      ],
    ),
  );
}

/// Cardio, target (or body part), equipment and "Mejor: 80 kg".
class _Tags extends StatelessWidget {
  const _Tags({required this.exercise, required this.cardio, required this.best});

  final Exercise exercise;
  final bool cardio;
  final num best;

  @override
  Widget build(BuildContext context) {
    final unit = context.select<AppState, String>((s) => s.settings.unit);
    final muscle = exercise.targetEs.isNotEmpty ? exercise.targetEs : exercise.bodyPartEs;
    final tags = [
      if (cardio) const Tag('Cardio', icon: 'figureRun', accent: true),
      if (muscle.isNotEmpty) Tag(muscle),
      if (exercise.equipmentEs.isNotEmpty) Tag(exercise.equipmentEs),
      if (best > 0) Tag('Mejor: ${formatWeight(best, unit)}', capitalize: false),
    ];
    if (tags.isEmpty) return const SizedBox(height: 2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: tags),
    );
  }
}

/// "La última vez (28 sept): 60×8, 60×8, 57,5×8".
class _LastTime extends StatelessWidget {
  const _LastTime({required this.entry});

  final ActiveEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final last = lastEntryFor(app.workouts, entry.id);
    if (last == null) return const SizedBox.shrink();
    final target = last.target;
    final cfg = target == null ? null : RoutineExercise.fromJson({...target, 'id': target['id'] ?? entry.id});
    final labels = last.sets.map((s) => setLabel(app.exerciseIndex, entry.id, s, cfg)).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        'La última vez (${formatDate(last.d)}): $labels',
        style: context.textStyles.small.copyWith(color: context.palette.label3),
      ),
    );
  }
}

/// Why the prefilled numbers are what they are: arrow up (more), arrow down in yellow
/// (deload), light bulb (same target, first session).
class _ProgressionLine extends StatelessWidget {
  const _ProgressionLine({required this.plan});

  final Prescription plan;

  @override
  Widget build(BuildContext context) {
    final text = plan.kind == 'off' ? null : whyText(plan.why);
    if (text == null) return const SizedBox.shrink();
    final p = context.palette;
    final color = plan.kind == 'deload' ? p.yellow : p.acc;
    final icon = switch (plan.kind) {
      'up' => 'arrowUp',
      'deload' => 'arrowDown',
      _ => 'lightbulb',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, height: 1.38, color: color)),
          ),
        ],
      ),
    );
  }
}
