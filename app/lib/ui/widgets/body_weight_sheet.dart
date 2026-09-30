import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/models/json.dart' show jsNum;
import '../theme.dart';
import 'app_icons.dart';
import 'buttons.dart';
import 'controls.dart';
import 'formatting.dart';
import 'pressable.dart';
import 'sheets.dart';
import 'surfaces.dart';

/// Lowest value [WeightInput] allows.
const weightInputMin = 1;

/// Highest value [WeightInput] allows: 300 kg or 660 lb.
num weightInputMax(String unit) => unit == 'lb' ? 660 : 300;

/// Rounds to 0.1 like every weight input (`Math.round(x * 10) / 10`).
num roundWeight(num value) => jsNum((value * 10).round() / 10);

/// The weight picker shared by the body-weight, goal and top-weight sheets (specs/ui.md §4.2):
/// ±0.1 buttons around a big readout, −1/−0.5/+0.5/+1 chips and a slider (step 0.5).
/// Every control clamps to `1 … 300 kg / 660 lb` and rounds to 0.1.
class WeightInput extends StatelessWidget {
  const WeightInput({super.key, required this.value, required this.onChanged, required this.unit});

  final num value;
  final ValueChanged<num> onChanged;
  final String unit;

  num _clamp(num x) => roundWeight(x).clamp(weightInputMin, weightInputMax(unit));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    Widget round(String icon, num delta, String label) => Pressable(
      onTap: () => onChanged(_clamp(value + delta)),
      pressedScale: .92,
      color: p.surface,
      pressedColor: p.surface2,
      borderRadius: BorderRadius.circular(23),
      semanticLabel: label,
      child: SizedBox.square(
        dimension: 46,
        child: Center(child: AppIcon(icon, size: 19, color: p.label)),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            round('minus', -0.1, 'Menos 0,1'),
            const SizedBox(width: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 158),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: formatNum(value), style: t.weightReadout),
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(fontSize: 19, color: p.label2),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 18),
            round('plus', 0.1, 'Más 0,1'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (label, delta) in const [('−1', -1), ('−0,5', -0.5), ('+0,5', 0.5), ('+1', 1)]) ...[
              AppChip(label, capitalize: false, onTap: () => onChanged(_clamp(value + delta))),
              const SizedBox(width: 7),
            ],
          ],
        ),
        const SizedBox(height: 8),
        AppSlider(
          value: value.clamp(weightInputMin, weightInputMax(unit)),
          min: weightInputMin,
          max: weightInputMax(unit),
          step: 0.5,
          onChanged: (v) => onChanged(_clamp(v)),
        ),
      ],
    );
  }
}

/// Colour of a body-weight change (`bwDeltaColor`): no change → label-2; no goal → label;
/// towards the goal → accent; away from it → red.
Color bodyWeightDeltaColor(BuildContext context, num delta, num currentWeight, num? targetWeight) {
  final p = context.palette;
  if (delta == 0) return p.label2;
  if (targetWeight == null || targetWeight == 0) return p.label;
  final up = targetWeight > currentWeight;
  return (delta > 0) == up ? p.acc : p.red;
}

/// What the owner chose in the pre-workout check-in.
class CheckInResult {
  const CheckInResult._(this.start, this.bodyWeight);

  /// Start the workout with the weight just saved.
  const CheckInResult.weighed(num weight) : this._(true, weight);

  /// "Empezar sin pesarse": start with `bw: null`.
  const CheckInResult.unweighed() : this._(true, null);

  /// "Elegir otro entrenamiento": start nothing; open the start chooser instead.
  const CheckInResult.chooseOther() : this._(false, null);

  /// Whether to start the workout.
  final bool start;

  /// The saved weigh-in to store on the workout (`bw`), or null.
  final num? bodyWeight;
}

/// "Registrar peso corporal" (specs/ui.md §4.3). Saves today's weigh-in and resolves to the
/// saved weight; null when dismissed.
///
/// With [required] it becomes the locked "Chequeo rápido" before a workout: it can only be
/// left through "Guardar y empezar" (→ the weight) or "Empezar sin pesarse" (→ null). Use
/// [showCheckInSheet] to also offer "Elegir otro entrenamiento".
Future<num?> showBodyWeightSheet(BuildContext context, {bool required = false}) async {
  if (!required) {
    return showAppSheet<num>(context, builder: (_) => const _BodyWeightSheet(mode: _Mode.log));
  }
  final result = await showAppSheet<CheckInResult>(
    context,
    locked: true,
    builder: (_) => const _BodyWeightSheet(mode: _Mode.requiredOnly),
  );
  return result?.bodyWeight;
}

/// The full pre-workout check-in (locked): "Guardar y empezar", "Empezar sin pesarse" and
/// "Elegir otro entrenamiento". The caller starts the workout when [CheckInResult.start].
Future<CheckInResult> showCheckInSheet(BuildContext context) async =>
    await showAppSheet<CheckInResult>(
      context,
      locked: true,
      builder: (_) => const _BodyWeightSheet(mode: _Mode.checkIn),
    ) ??
    const CheckInResult.chooseOther();

enum _Mode { log, requiredOnly, checkIn }

class _BodyWeightSheet extends StatefulWidget {
  const _BodyWeightSheet({required this.mode});

  final _Mode mode;

  @override
  State<_BodyWeightSheet> createState() => _BodyWeightSheetState();
}

class _BodyWeightSheetState extends State<_BodyWeightSheet> {
  late num _value;

  @override
  void initState() {
    super.initState();
    _value = context.read<AppState>().lastBodyWeight?.w ?? 70;
  }

  bool get _required => widget.mode != _Mode.log;

  void _save() {
    final app = context.read<AppState>();
    final n = roundWeight(_value);
    if (n <= 0) {
      showToast(context, 'Introduce un peso válido');
      return;
    }
    app.setBodyWeight(n);
    if (_required) {
      Navigator.of(context).pop(CheckInResult.weighed(n));
    } else {
      showToast(context, 'Peso guardado');
      Navigator.of(context).pop(n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final unit = app.settings.unit;
    final t = context.textStyles;
    final p = context.palette;
    final recent = app.bodyWeights.reversed.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(_required ? 'Chequeo rápido' : 'Registrar peso corporal'),
        Text(
          _required
              ? 'Desliza o toca para fijar tu peso — se registra antes de cada entrenamiento para que tu curva sea honesta.'
              : 'Hoy, ${formatDate(app.clock.todayIso(), long: true)}',
          style: t.small,
        ),
        WeightInput(value: _value, unit: unit, onChanged: (v) => setState(() => _value = v)),
        const SizedBox(height: 14),
        AppButton(_required ? 'Guardar y empezar' : 'Guardar', variant: ButtonVariant.primary, onPressed: _save),
        if (_required) ...[
          const SizedBox(height: 8),
          AppButton(
            'Empezar sin pesarse',
            variant: ButtonVariant.ghost,
            dim: true,
            onPressed: () => Navigator.of(context).pop(const CheckInResult.unweighed()),
          ),
        ],
        if (widget.mode == _Mode.checkIn) ...[
          const SizedBox(height: 2),
          AppButton(
            'Elegir otro entrenamiento',
            icon: 'reset',
            variant: ButtonVariant.ghost,
            dim: true,
            onPressed: () => Navigator.of(context).pop(const CheckInResult.chooseOther()),
          ),
        ],
        if (!_required && recent.isNotEmpty) ...[
          const SectionCaption('Pesajes recientes'),
          for (final b in recent)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.sep, width: .5)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(formatDate(b.d, long: true), style: t.small)),
                    Text(formatWeight(b.w, unit), style: t.body.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    AppIconButton(
                      icon: 'trash',
                      tooltip: 'Borrar pesaje',
                      size: 32,
                      iconSize: 16,
                      color: p.red,
                      borderRadius: BorderRadius.circular(8),
                      onPressed: () => app.deleteBodyWeight(b.d),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// "Peso objetivo" (specs/ui.md §4.4): sets or removes `settings.targetW`.
Future<void> showGoalSheet(BuildContext context) => showAppSheet<void>(context, builder: (_) => const _GoalSheet());

class _GoalSheet extends StatefulWidget {
  const _GoalSheet();

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late num _value;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _value = app.settings.targetW ?? app.lastBodyWeight?.w ?? 70;
  }

  void _save() {
    final app = context.read<AppState>();
    final n = roundWeight(_value);
    if (n <= 0) {
      showToast(context, 'Introduce un peso válido');
      return;
    }
    app.updateSettings((s) => s.targetW = n);
    final unit = app.settings.unit;
    final last = app.lastBodyWeight;
    final toGo = last == null ? '' : ' (faltan ${formatNum((n - last.w).abs())})';
    showToast(context, 'Meta fijada: ${formatWeight(n, unit)}$toGo');
    Navigator.of(context).pop();
  }

  void _remove() {
    context.read<AppState>().updateSettings((s) => s.targetW = null);
    showToast(context, 'Meta eliminada');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.select<AppState, (String, num?)>((s) => (s.settings.unit, s.settings.targetW));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle('Peso objetivo'),
        Text(
          'Tu meta se dibuja como una línea en las gráficas de peso, y las subidas/bajadas se colorean según se acerquen a ella.',
          style: context.textStyles.small,
        ),
        WeightInput(value: _value, unit: settings.$1, onChanged: (v) => setState(() => _value = math.max(v, 0))),
        const SizedBox(height: 14),
        AppButton('Guardar meta', variant: ButtonVariant.primary, onPressed: _save),
        if (settings.$2 != null) ...[
          const SizedBox(height: 8),
          AppButton('Eliminar meta', variant: ButtonVariant.danger, onPressed: _remove),
        ],
      ],
    );
  }
}
