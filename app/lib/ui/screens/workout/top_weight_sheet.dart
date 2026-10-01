import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'set_editing.dart';
import 'workout_controller.dart';

/// The top-weight confirmation (specs/ui.md §5.9), shown the first time every set of a reps
/// entry is done: confirm the weight worked with, which becomes the working weight. Resolves to
/// what saving led to, or null when dismissed. The sheet closes itself if its entry disappears
/// (the workout ended underneath it).
Future<TopWeightOutcome?> showTopWeightSheet(BuildContext context, int entryIndex) =>
    showAppSheet<TopWeightOutcome>(context, builder: (_) => _TopWeightSheet(entryIndex: entryIndex));

class _TopWeightSheet extends StatefulWidget {
  const _TopWeightSheet({required this.entryIndex});

  final int entryIndex;

  @override
  State<_TopWeightSheet> createState() => _TopWeightSheetState();
}

class _TopWeightSheetState extends State<_TopWeightSheet> {
  late num _value;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final entry = app.active?.entries.elementAtOrNull(widget.entryIndex);
    _value = entry == null ? 0 : topWeightSuggestion(app.trainingState, entry);
  }

  void _commit({required bool advance}) {
    final outcome = context.read<WorkoutController>().saveTopWeight(widget.entryIndex, _value, advance: advance);
    if (outcome == TopWeightOutcome.invalid) {
      showToast(context, 'Introduce un peso válido');
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  void _closeSoon() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.active;
    final entry = active?.entries.elementAtOrNull(widget.entryIndex);
    if (active == null || entry == null) {
      _closeSoon();
      return const SizedBox(height: 120);
    }
    final p = context.palette;
    final t = context.textStyles;
    final unit = app.settings.unit;
    final units = unitsOf(active);
    final unitIndex = units.indexWhere((u) => u.contains(widget.entryIndex));
    final group = units[unitIndex];
    final done = unitDone(active, group);
    final isLastUnit = unitIndex >= units.length - 1;
    final maxSet = entry.sets.where((s) => s.done).fold<num>(0, (m, s) => math.max(m, s.w ?? 0));
    final prevBest = previousBest(app.trainingState, entry);
    final name = capitalizeWords(app.catalog.exOr(entry.id).name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle('$name hecho', leading: AppIcon('checkCircle', size: 22, color: p.acc)),
        Text(
          'Confirma el peso con el que trabajaste — el más alto será el predeterminado la próxima vez.'
          '${!done && group.length > 1 ? ' Luego termina el otro ejercicio de la superserie.' : ''}',
          style: t.small,
        ),
        WeightInput(value: _value, unit: unit, onChanged: (v) => setState(() => _value = v)),
        const SizedBox(height: 10),
        if (prevBest > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(
              TextSpan(
                text: 'Mejor anterior: ${formatWeight(prevBest, unit)}',
                children: [
                  if (maxSet > prevBest)
                    TextSpan(
                      text: ' — ¡nuevo récord!',
                      style: TextStyle(color: p.yellow),
                    ),
                ],
              ),
              textAlign: TextAlign.center,
              style: t.small.copyWith(color: p.label3),
            ),
          )
        else
          const SizedBox(height: 4),
        if (done) ...[
          AppButton(
            isLastUnit ? 'Guardar' : 'Guardar y siguiente ejercicio',
            variant: ButtonVariant.primary,
            trailingIcon: isLastUnit ? null : 'chevronRight',
            onPressed: () => _commit(advance: true),
          ),
          const SizedBox(height: 8),
          AppButton('Solo cerrar', variant: ButtonVariant.ghost, dim: true, onPressed: () => _commit(advance: false)),
        ] else
          AppButton('Guardar peso', variant: ButtonVariant.primary, onPressed: () => _commit(advance: false)),
      ],
    );
  }
}
