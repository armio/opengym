import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'services/workout_timers.dart';
import 'set_editing.dart';
import 'workout_controller.dart';

/// One stepper column of the set table (specs/ui.md §5.5).
class SetColumn {
  const SetColumn({required this.field, required this.step, required this.decimal, required this.header, this.effort});

  final String field;
  final num step;
  final bool decimal;

  /// Column header (shown uppercase).
  final String header;

  /// `'rir'` / `'rpe'` for the effort column: its own scale, nullable, typed values capped.
  final String? effort;

  bool get isEffort => effort != null;
}

/// The columns of an entry logged in [mode]: weight × reps (+ RIR/RPE when the profile logs
/// effort), seconds + weight, or minutes + speed.
List<SetColumn> setColumnsFor(String mode, {required String unit, required String effortScale}) {
  final weight = SetColumn(field: SetField.w, step: 2.5, decimal: true, header: 'Peso ($unit)');
  switch (mode) {
    case ExerciseMode.cardio:
      return const [
        SetColumn(field: SetField.min, step: 1, decimal: false, header: 'Duración (min)'),
        SetColumn(field: SetField.speed, step: 0.5, decimal: true, header: 'Velocidad (km/h)'),
      ];
    case ExerciseMode.time:
      return [const SetColumn(field: SetField.sec, step: 5, decimal: false, header: 'Segundos'), weight];
    default:
      final scale = effortScales[effortScale];
      return [
        weight,
        const SetColumn(field: SetField.r, step: 1, decimal: false, header: 'Reps'),
        if (scale != null)
          SetColumn(field: scale.field, step: scale.step, decimal: true, header: scale.label, effort: effortScale),
      ];
  }
}

/// Row geometry: with an effort column the row tightens (gap 6, flex 1.2 / 1 / 0.85, narrower
/// stepper buttons, 14 px values); timed rows make room for the play button.
class _RowLayout {
  const _RowLayout({required this.gap, required this.flex, required this.buttonWidth, required this.fontSize});

  factory _RowLayout.of(List<SetColumn> columns, {required bool timed}) {
    if (columns.length > 2) {
      return const _RowLayout(gap: 6, flex: [24, 20, 17], buttonWidth: [23, 23, 20], fontSize: 14);
    }
    final button = timed ? 28.0 : 32.0;
    return _RowLayout(gap: 8, flex: const [14, 10], buttonWidth: [button, button], fontSize: 17);
  }

  final double gap;
  final List<int> flex;
  final List<double> buttonWidth;
  final double fontSize;
}

/// The set table card of one entry: header, a row per set (number, steppers, ▶ for timed
/// sets, check) and "Quitar serie" / "Añadir serie".
class SetTable extends StatelessWidget {
  const SetTable({
    super.key,
    required this.entryIndex,
    required this.entry,
    required this.columns,
    required this.timed,
  });

  final int entryIndex;
  final ActiveEntry entry;
  final List<SetColumn> columns;
  final bool timed;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<WorkoutController>();
    final holding = context.select<WorkoutTimers, bool>((t) => t.hold != null);
    final layout = _RowLayout.of(columns, timed: timed);
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeaderRow(columns: columns, layout: layout, timed: timed),
          for (var i = 0; i < entry.sets.length; i++) ...[
            if (i > 0) Divider(height: .5, thickness: .5, indent: 32, color: p.sep),
            _SetRow(
              key: ValueKey('set-$entryIndex-$i'),
              number: i + 1,
              set: entry.sets[i],
              columns: columns,
              layout: layout,
              timed: timed,
              canStartHold: !holding,
              onField: (field, value) => controller.setField(entryIndex, i, field, value),
              onToggle: () => controller.toggle(entryIndex, i),
              onStartHold: () => controller.startHold(entryIndex, i),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              AppButton(
                'Quitar serie',
                icon: 'minus',
                size: ButtonSize.sm,
                onPressed: entry.sets.length > 1 ? () => controller.removeSetFrom(entryIndex) : null,
              ),
              AppButton(
                'Añadir serie',
                icon: 'plus',
                size: ButtonSize.sm,
                onPressed: () => controller.addSetTo(entryIndex),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns, required this.layout, required this.timed});

  final List<SetColumn> columns;
  final _RowLayout layout;
  final bool timed;

  @override
  Widget build(BuildContext context) {
    final style = context.textStyles.microCaps.copyWith(letterSpacing: 11 * .045);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: 24),
          for (var c = 0; c < columns.length; c++) ...[
            SizedBox(width: layout.gap),
            Expanded(
              flex: layout.flex[c],
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(columns[c].header.toUpperCase(), maxLines: 1, style: style),
              ),
            ),
          ],
          if (timed) SizedBox(width: layout.gap + 30),
          SizedBox(width: layout.gap + 30),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    super.key,
    required this.number,
    required this.set,
    required this.columns,
    required this.layout,
    required this.timed,
    required this.canStartHold,
    required this.onField,
    required this.onToggle,
    required this.onStartHold,
  });

  final int number;
  final SetRecord set;
  final List<SetColumn> columns;
  final _RowLayout layout;
  final bool timed;
  final bool canStartHold;
  final void Function(String field, num? value) onField;
  final VoidCallback onToggle;
  final VoidCallback onStartHold;

  /// On narrow phones the ± buttons give way so the value ("62.5") keeps its room.
  Widget _stepper(BuildContext context, int c) => LayoutBuilder(
    builder: (context, box) {
      final room = (box.maxWidth - layout.fontSize * 2.2) / 2;
      return _stepperWith(context, c, room.clamp(16.0, layout.buttonWidth[c]).toDouble());
    },
  );

  Widget _stepperWith(BuildContext context, int c, double buttonWidth) {
    final col = columns[c];
    final p = context.palette;
    return ValueStepper(
      value: setFieldOf(set, col.field),
      step: col.step,
      decimal: col.decimal,
      nullable: col.isEffort,
      buttonWidth: buttonWidth,
      height: 40,
      valueStyle: TextStyle(fontSize: layout.fontSize, fontWeight: FontWeight.w500, color: p.label),
      stepper: col.isEffort ? (cur, dir) => stepEffort(col.effort, cur, dir) : null,
      onChanged: (v) => onField(col.field, col.isEffort ? capEffort(col.effort, v) : v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedOpacity(
      opacity: set.done ? .45 : 1,
      duration: AppMotion.fast,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            _SetNumber(number: number, done: set.done),
            for (var c = 0; c < columns.length; c++) ...[
              SizedBox(width: layout.gap),
              Expanded(flex: layout.flex[c], child: _stepper(context, c)),
            ],
            if (timed) ...[
              SizedBox(width: layout.gap),
              AppIconButton(
                icon: 'play',
                tooltip: 'Iniciar serie',
                size: 30,
                iconSize: 14,
                color: p.acc,
                background: p.surface2,
                onPressed: set.done || !canStartHold ? null : onStartHold,
              ),
            ],
            SizedBox(width: layout.gap),
            RoundCheck(value: set.done, onChanged: (_) => onToggle(), semanticLabel: 'Serie $number hecha'),
          ],
        ),
      ),
    );
  }
}

/// The set number bubble; accent once the set is done.
class _SetNumber extends StatelessWidget {
  const _SetNumber({required this.number, required this.done});

  final int number;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: AppMotion.fast,
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: done ? p.acc : p.surface2, shape: BoxShape.circle),
      child: Text(
        '$number',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: done ? p.onAcc : p.label2),
      ),
    );
  }
}
