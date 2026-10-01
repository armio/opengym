import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/library.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../library/library_screen.dart' show showCustomExerciseSheet;

/// What the exercise config sheet ended with (null = dismissed).
sealed class ExerciseConfigResult {
  const ExerciseConfigResult();
}

/// "Guardar" / "Añadir a la rutina": the normalised config ([saveExerciseConfig]). Its `id` is
/// the exercise's and it carries no `sg` — when replacing an entry, keep that entry's `sg`.
final class ExerciseConfigSaved extends ExerciseConfigResult {
  const ExerciseConfigSaved(this.config);

  final RoutineExercise config;
}

/// "Quitar de la rutina" (only offered with `allowDelete`).
final class ExerciseConfigRemoved extends ExerciseConfigResult {
  const ExerciseConfigRemoved();
}

/// The exercise config sheet (specs/ui.md §4.9): media, taxonomy tags, reps/time switch (not for
/// cardio, which is decided by the body part — critic-G4), the steppers of the mode, the
/// progression rule, step and rep range, then save / edit custom exercise / remove.
///
/// [existing] is the entry being edited (null = adding [exercise]); [routine] is where the
/// entry lives, for the inherited progression policy (the routine being edited, or the active
/// workout's routine). [saveLabel] overrides the button text for a new entry ("Añadir a la
/// rutina"). For a custom exercise, "Editar o eliminar este ejercicio" closes this sheet
/// (resolving to null) and opens the custom exercise form.
Future<ExerciseConfigResult?> showExerciseConfigSheet(
  BuildContext context, {
  required Exercise exercise,
  RoutineExercise? existing,
  Routine? routine,
  bool allowDelete = false,
  String? saveLabel,
}) async {
  final outcome = await showAppSheet<_SheetOutcome>(
    context,
    builder: (_) => _ExerciseConfigForm(
      exercise: exercise,
      existing: existing,
      routine: routine,
      allowDelete: allowDelete,
      saveLabel: saveLabel ?? (existing == null ? 'Añadir a la rutina' : 'Guardar'),
    ),
  );
  switch (outcome) {
    case _Done(:final result):
      return result;
    case _EditCustom():
      if (context.mounted) {
        final current = context.read<AppState>().catalog.byId(exercise.id);
        if (current != null) await showCustomExerciseSheet(context, existing: current);
      }
      return null;
    case null:
      return null;
  }
}

sealed class _SheetOutcome {
  const _SheetOutcome();
}

class _Done extends _SheetOutcome {
  const _Done(this.result);

  final ExerciseConfigResult result;
}

class _EditCustom extends _SheetOutcome {
  const _EditCustom();
}

// ---------------------------------------------------------------------------------------------
// Form rules (pure).

/// The logging mode the form shows: cardio by body part only, else time or reps. A non-cardio
/// entry stored as `cardio` (critic-G4) is shown — and saved — as reps.
String configFormMode(ExerciseIndex index, Exercise exercise, RoutineExercise c) {
  if (exercise.isCardio) return ExerciseMode.cardio;
  return modeOf(index, c) == ExerciseMode.time ? ExerciseMode.time : ExerciseMode.reps;
}

/// The form's starting state: a copy of [existing], or `defaultConfig(id)` for a new entry.
/// Values Save would default anyway are filled in so the steppers show them (cardio minutes and
/// speed; the reps fields of a non-cardio entry stored as cardio).
RoutineExercise initialConfigDraft(ExerciseIndex index, Exercise exercise, RoutineExercise? existing) {
  final c = existing?.copy() ?? defaultConfig(index, exercise.id);
  c.id = exercise.id;
  if (exercise.isCardio) {
    c
      ..min ??= 20
      ..speed ??= 8;
    return c;
  }
  final mode = configFormMode(index, exercise, c);
  return c.mode == mode ? c : withConfigMode(index, c, mode);
}

/// `setMode(m)`: `{...defaultConfig(id, m), ...c, mode: m}` — keeps every value the form already
/// has and fills only the missing ones.
RoutineExercise withConfigMode(ExerciseIndex index, RoutineExercise c, String mode) {
  final d = defaultConfig(index, c.id, mode);
  return c.copy()
    ..mode = mode
    ..reps ??= d.reps
    ..sec ??= d.sec
    ..min ??= d.min
    ..speed ??= d.speed
    ..weight ??= d.weight;
}

/// `ExConfig.save` (specs/data-model.md §1.4.2): what the sheet writes for form state [c] in
/// [mode]. Cardio keeps only sets/min/speed (no mode, no progression); time and reps always
/// write `mode`; `prog` / `inc` only when set; `repsMin` only when the effective policy is
/// `double`. JavaScript's `round(x) || fallback` makes 0 and blanks take the default.
RoutineExercise saveExerciseConfig(ExerciseIndex index, RoutineExercise c, {required String mode, Routine? routine}) {
  final cardio = mode == ExerciseMode.cardio;
  final sets = math.max(1, _roundOr(c.sets, cardio ? 1 : 3));
  if (cardio) {
    return RoutineExercise(
      id: c.id,
      sets: sets,
      min: math.max(1, _roundOr(c.min, 20)),
      speed: math.max(0, numOr(c.speed, 8)),
    );
  }
  final prog = c.prog == null || c.prog!.isEmpty ? null : c.prog;
  final inc = (c.inc ?? 0) > 0 ? c.inc : null;
  final weight = math.max<num>(0, numOr(c.weight, 0));
  if (mode == ExerciseMode.time) {
    return RoutineExercise(
      id: c.id,
      sets: sets,
      mode: ExerciseMode.time,
      sec: math.max(1, _roundOr(c.sec, 45)),
      weight: weight,
      prog: prog,
      inc: inc,
    );
  }
  final reps = math.max(1, _roundOr(c.reps, 10));
  final double = policyFor(index, c, routine, ExerciseMode.reps) == 'double';
  return RoutineExercise(
    id: c.id,
    sets: sets,
    mode: ExerciseMode.reps,
    reps: reps,
    weight: weight,
    prog: prog,
    inc: inc,
    repsMin: double ? math.min(reps, math.max(1, _roundOr(c.repsMin, math.max(1, reps - 2)))) : null,
  );
}

/// `Math.round(v) || fallback`.
int _roundOr(num? v, int fallback) {
  if (v == null || !v.isFinite) return fallback;
  final r = jsRound(v).toInt();
  return r == 0 ? fallback : r;
}

// ---------------------------------------------------------------------------------------------
// The sheet.

class _ExerciseConfigForm extends StatefulWidget {
  const _ExerciseConfigForm({
    required this.exercise,
    required this.existing,
    required this.routine,
    required this.allowDelete,
    required this.saveLabel,
  });

  final Exercise exercise;
  final RoutineExercise? existing;
  final Routine? routine;
  final bool allowDelete;
  final String saveLabel;

  @override
  State<_ExerciseConfigForm> createState() => _ExerciseConfigFormState();
}

class _ExerciseConfigFormState extends State<_ExerciseConfigForm> {
  late final ExerciseIndex _index;
  late RoutineExercise _c;

  @override
  void initState() {
    super.initState();
    _index = context.read<AppState>().exerciseIndex;
    _c = initialConfigDraft(_index, widget.exercise, widget.existing);
  }

  Exercise get _ex => widget.exercise;
  String get _mode => configFormMode(_index, _ex, _c);

  void _edit(void Function(RoutineExercise c) fn) => setState(() => fn(_c));

  void _pop(_SheetOutcome outcome) => Navigator.of(context).pop(outcome);

  void _save() =>
      _pop(_Done(ExerciseConfigSaved(saveExerciseConfig(_index, _c, mode: _mode, routine: widget.routine))));

  @override
  Widget build(BuildContext context) {
    final unit = context.select<AppState, String>((s) => s.settings.unit);
    final mode = _mode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(capitalizeWords(_ex.name)),
        ExerciseMedia(exercise: _ex),
        _ExerciseTags(exercise: _ex),
        if (_ex.desc.isNotEmpty) _Note(_ex.desc),
        if (mode != ExerciseMode.cardio) ...[
          Segmented<String>(
            segments: const [Segment(ExerciseMode.reps, 'Reps'), Segment(ExerciseMode.time, 'Tiempo')],
            value: mode,
            onChanged: (m) => setState(() => _c = withConfigMode(_index, _c, m)),
          ),
          const SizedBox(height: 14),
        ],
        _TargetSteppers(mode: mode, config: _c, unit: unit, onEdit: _edit),
        if (mode == ExerciseMode.time)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Un temporizador corre mientras aguantas la serie. Deja el peso en 0 para isométricos con tu propio peso.',
              style: context.textStyles.small.copyWith(color: context.palette.label3),
            ),
          ),
        const SizedBox(height: 18),
        if (mode != ExerciseMode.cardio)
          _ProgressionFields(index: _index, mode: mode, config: _c, routine: widget.routine, unit: unit, onEdit: _edit),
        AppButton(widget.saveLabel, variant: ButtonVariant.primary, onPressed: _save),
        if (_ex.custom) ...[
          const SizedBox(height: 8),
          AppButton('Editar o eliminar este ejercicio', icon: 'pencil', onPressed: () => _pop(const _EditCustom())),
        ],
        if (widget.allowDelete) ...[
          const SizedBox(height: 8),
          AppButton(
            'Quitar de la rutina',
            variant: ButtonVariant.danger,
            onPressed: () => _pop(const _Done(ExerciseConfigRemoved())),
          ),
        ],
      ],
    );
  }
}

/// Cardio tag, then the target muscle (or body part) and the equipment, in Spanish.
class _ExerciseTags extends StatelessWidget {
  const _ExerciseTags({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final ex = exercise;
    final what = ex.targetEs.isNotEmpty ? ex.targetEs : ex.bodyPartEs;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (ex.isCardio) const Tag('Cardio', icon: 'figureRun', accent: true),
          if (what.isNotEmpty) Tag(what),
          if (ex.equipmentEs.isNotEmpty) Tag(ex.equipmentEs),
        ],
      ),
    );
  }
}

/// A custom exercise's description (`.exnote`).
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(AppRadii.r)),
      child: Text(text, style: TextStyle(fontSize: 15, height: 1.45, color: p.label2)),
    );
  }
}

/// A row of equal-width labelled steppers (`.cfgrow`: gap 8, 30 px buttons).
class _StepperRow extends StatelessWidget {
  const _StepperRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: children[i])],
    ],
  );
}

/// One labelled stepper of the config sheet.
class _ConfigStepper extends StatelessWidget {
  const _ConfigStepper({required this.label, required this.value, required this.step, required this.onChanged});

  final String label;
  final num? value;
  final num step;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) => ValueStepper(
    label: label,
    value: value,
    step: step,
    decimal: step != step.roundToDouble(),
    buttonWidth: 30,
    onChanged: (v) => onChanged(v ?? 0),
  );
}

/// Sets and the target of the mode: intervals/minutes/speed, sets/seconds/weight or
/// sets/reps/weight.
class _TargetSteppers extends StatelessWidget {
  const _TargetSteppers({required this.mode, required this.config, required this.unit, required this.onEdit});

  final String mode;
  final RoutineExercise config;
  final String unit;
  final void Function(void Function(RoutineExercise c) fn) onEdit;

  @override
  Widget build(BuildContext context) {
    final c = config;
    Widget sets(String label) =>
        _ConfigStepper(label: label, value: c.sets, step: 1, onChanged: (v) => onEdit((c) => c.sets = v.round()));
    Widget weight() => _ConfigStepper(
      label: 'Peso ($unit)',
      value: c.weight,
      step: 2.5,
      onChanged: (v) => onEdit((c) => c.weight = v),
    );
    return _StepperRow(
      children: switch (mode) {
        ExerciseMode.cardio => [
          sets('Intervalos'),
          _ConfigStepper(label: 'Minutos', value: c.min, step: 1, onChanged: (v) => onEdit((c) => c.min = v)),
          _ConfigStepper(
            label: 'Velocidad (km/h)',
            value: c.speed,
            step: .5,
            onChanged: (v) => onEdit((c) => c.speed = v),
          ),
        ],
        ExerciseMode.time => [
          sets('Series'),
          _ConfigStepper(label: 'Segundos', value: c.sec, step: 5, onChanged: (v) => onEdit((c) => c.sec = v)),
          weight(),
        ],
        _ => [
          sets('Series'),
          _ConfigStepper(label: 'Reps', value: c.reps, step: 1, onChanged: (v) => onEdit((c) => c.reps = v)),
          weight(),
        ],
      },
    );
  }
}

/// "Progresión": the rule (follow the routine, or a policy of the mode), its description, and —
/// unless the rule is off — the step and, for double progression, the bottom of the rep range.
class _ProgressionFields extends StatelessWidget {
  const _ProgressionFields({
    required this.index,
    required this.mode,
    required this.config,
    required this.routine,
    required this.unit,
    required this.onEdit,
  });

  final ExerciseIndex index;
  final String mode;
  final RoutineExercise config;
  final Routine? routine;
  final String unit;
  final void Function(void Function(RoutineExercise c) fn) onEdit;

  @override
  Widget build(BuildContext context) {
    final c = config;
    final p = context.palette;
    final timed = mode == ExerciseMode.time;
    final inherited = policyFor(index, RoutineExercise(id: c.id), routine, mode);
    final active = policyFor(index, c, routine, mode);
    final inc = (c.inc ?? 0) > 0 ? c.inc! : (timed ? defaultSecIncrement : defaultIncrement(index, c.id, unit));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionCaption('Progresión'),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: ColoredBox(
            color: p.surface,
            child: SelectRow<String>(
              title: 'Regla',
              sheetTitle: 'Progresión',
              value: c.prog ?? '',
              options: [
                SelectOption('', 'Seguir la rutina (${policyNames[inherited]})'),
                for (final policy in policiesFor[mode] ?? const ['off']) SelectOption(policy, policyNames[policy]!),
              ],
              onChanged: (v) => onEdit((c) => c.prog = v.isEmpty ? null : v),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(2, 8, 2, active == 'off' ? 18 : 10),
          child: Text(policyDescriptions[active] ?? '', style: context.textStyles.small.copyWith(color: p.label3)),
        ),
        if (active != 'off') ...[
          _StepperRow(
            children: [
              _ConfigStepper(
                label: timed ? 'Incremento (segundos)' : 'Incremento ($unit)',
                value: inc,
                step: timed ? 5 : 1.25,
                onChanged: (v) => onEdit((c) => c.inc = v),
              ),
              if (active == 'double')
                _ConfigStepper(
                  label: 'Reps desde',
                  value: numOr(c.repsMin, math.max(1, numOr(c.reps, 10) - 2)),
                  step: 1,
                  onChanged: (v) => onEdit((c) => c.repsMin = v),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}
