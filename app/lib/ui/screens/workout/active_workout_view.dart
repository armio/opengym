import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'elapsed_text.dart';
import 'exercise_block.dart';
import 'services/workout_timers.dart';
import 'set_editing.dart';
import 'timer_bar.dart';
import 'top_weight_sheet.dart';
import 'workout_controller.dart';
import 'workout_flows.dart';

/// The workout in progress (specs/ui.md §5.4): header with the running clock, progress, the
/// current exercise or superset, Anterior / Siguiente by unit, "Añadir ejercicio", the finish
/// button, and the floating timer bar. It shows the controller's prompts (top weight, the
/// "whole workout" dialog, toasts).
class ActiveWorkoutView extends StatefulWidget {
  const ActiveWorkoutView({super.key});

  @override
  State<ActiveWorkoutView> createState() => _ActiveWorkoutViewState();
}

class _ActiveWorkoutViewState extends State<ActiveWorkoutView> {
  StreamSubscription<WorkoutPrompt>? _prompts;

  @override
  void initState() {
    super.initState();
    _prompts = context.read<WorkoutController>().prompts.listen(_onPrompt);
  }

  @override
  void dispose() {
    _prompts?.cancel();
    super.dispose();
  }

  Future<void> _onPrompt(WorkoutPrompt prompt) async {
    if (!mounted) return;
    switch (prompt) {
      case AskTopWeight(:final entry):
        final outcome = await showTopWeightSheet(context, entry);
        if (outcome == TopWeightOutcome.completed && mounted) await showWorkoutCompleteDialog(context);
      case WorkoutCompleted():
        await showWorkoutCompleteDialog(context);
      case WorkoutToast(:final message):
        showToast(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = context.select<AppState, ActiveWorkout?>((s) => s.active);
    if (active == null) return const SizedBox.shrink();
    final timing = context.select<WorkoutTimers, bool>((t) => t.isRunning);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          PageBody(
            bottomPadding: timing ? 170 : 40,
            children: [
              _Header(active: active),
              _ProgressBar(active: active),
              if (active.entries.isEmpty)
                const EmptyState(icon: 'shuffle', message: 'Entrenamiento libre — añade tu primer ejercicio.')
              else
                _CurrentUnit(active: active),
              const SizedBox(height: 12),
              _UnitNavigation(active: active),
              const SizedBox(height: 10),
              AppButton('Añadir ejercicio', icon: 'plus', onPressed: () => addExerciseToWorkout(context)),
              const SizedBox(height: 10),
              _FinishButton(active: active),
            ],
          ),
          Positioned(left: 12, right: 12, bottom: 12 + bottom, child: const WorkoutTimerBar()),
        ],
      ),
    );
  }
}

/// ✕ (discard) · name and "12:03 · 5/18 series" · ✓ (finish). A chevron leaves the screen with
/// the workout still running (the tab bar's "Seguir" brings it back).
class _Header extends StatelessWidget {
  const _Header({required this.active});

  final ActiveWorkout active;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    final navigator = Navigator.of(context);
    final done = setsDoneActive(active), total = setsTotalActive(active);
    const side = 36.0 * 2 + 8;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: side,
            child: Row(
              children: [
                if (ModalRoute.of(context)?.isFirst == false) ...[
                  AppIconButton(icon: 'chevronDown', tooltip: 'Ocultar', onPressed: navigator.pop),
                  const SizedBox(width: 8),
                ],
                AppIconButton(icon: 'xmark', tooltip: 'Descartar', onPressed: () => discardWorkout(context)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  active.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.rowTitle.copyWith(fontWeight: FontWeight.w600),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(child: ElapsedText(start: active.start)),
                      TextSpan(text: ' · $done/$total series'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: t.subtitle,
                ),
              ],
            ),
          ),
          SizedBox(
            width: side,
            child: Align(
              alignment: Alignment.centerRight,
              child: AppIconButton(
                icon: 'check',
                tooltip: 'Terminar',
                color: context.palette.acc,
                onPressed: () => finishWorkoutFlow(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Done sets out of all sets.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.active});

  final ActiveWorkout active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = setsTotalActive(active);
    final fraction = total == 0 ? 0.0 : setsDoneActive(active) / total;
    return Container(
      height: 4,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(99)),
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: AppMotion.med,
        curve: AppMotion.ease,
        widthFactor: fraction,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: p.acc, borderRadius: BorderRadius.circular(99)),
        ),
      ),
    );
  }
}

/// "Ejercicio 2 / 5" or "Superserie 1 / 4", then the exercise — or the superset card with its
/// members in compact form.
class _CurrentUnit extends StatelessWidget {
  const _CurrentUnit({required this.active});

  final ActiveWorkout active;

  @override
  Widget build(BuildContext context) {
    final units = unitsOf(active);
    final cur = currentIndex(active);
    final unitIndex = units.indexWhere((u) => u.contains(cur));
    final unit = units[unitIndex];
    final superset = unit.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            superset ? 'Superserie ${unitIndex + 1} / ${units.length}' : 'Ejercicio ${unitIndex + 1} / ${units.length}',
            style: context.textStyles.small,
          ),
        ),
        if (superset) _SupersetCard(unit: unit) else ExerciseBlock(key: ValueKey('block-$cur'), entryIndex: cur),
      ],
    );
  }
}

class _SupersetCard extends StatelessWidget {
  const _SupersetCard({required this.unit});

  final List<int> unit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.acc);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: p.accLine, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon('link', size: 13, color: p.acc),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Superserie · hazlos seguidos, descansa después de ambos',
                    textAlign: TextAlign.center,
                    style: accent,
                  ),
                ),
              ],
            ),
          ),
          for (var k = 0; k < unit.length; k++) ...[
            if (k > 0)
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Text('+', textAlign: TextAlign.center, style: accent.copyWith(fontSize: 15)),
              ),
            ExerciseBlock(key: ValueKey('block-${unit[k]}'), entryIndex: unit[k], compact: true),
          ],
        ],
      ),
    );
  }
}

class _UnitNavigation extends StatelessWidget {
  const _UnitNavigation({required this.active});

  final ActiveWorkout active;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<WorkoutController>();
    final units = unitsOf(active);
    final unitIndex = active.entries.isEmpty ? -1 : units.indexWhere((u) => u.contains(currentIndex(active)));
    return Row(
      children: [
        Expanded(
          child: AppButton(
            'Anterior',
            icon: 'chevronLeft',
            onPressed: unitIndex > 0 ? () => controller.moveBy(-1) : null,
          ),
        ),
        Expanded(
          child: AppButton(
            'Siguiente',
            trailingIcon: 'chevronRight',
            onPressed: unitIndex >= 0 && unitIndex < units.length - 1 ? () => controller.moveBy(1) : null,
          ),
        ),
      ],
    );
  }
}

/// Primary "Terminar entrenamiento" once every exercise is done, else a dim "Terminar antes ·
/// 2/5 ejercicios".
class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.active});

  final ActiveWorkout active;

  @override
  Widget build(BuildContext context) {
    final exDone = active.entries.where((e) => e.sets.isNotEmpty && e.sets.every((s) => s.done)).length;
    final allDone = active.entries.isNotEmpty && exDone == active.entries.length;
    return allDone
        ? AppButton(
            'Terminar entrenamiento',
            variant: ButtonVariant.primary,
            onPressed: () => finishWorkoutFlow(context),
          )
        : AppButton(
            'Terminar antes · $exDone/${active.entries.length} ejercicios',
            variant: ButtonVariant.ghost,
            dim: true,
            onPressed: () => finishWorkoutFlow(context),
          );
  }
}
