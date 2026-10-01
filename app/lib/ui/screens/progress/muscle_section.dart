import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'progress_widgets.dart';

/// "Músculos" (specs/ui.md §3.6 "Muscle balance", engine.md §8.4): which muscles a window of
/// training hit — and, the point of it, which ones it keeps missing. The map shades relative
/// to the hardest-worked muscle; "Duras" counts only sets taken near failure and is offered only
/// when the window holds such sets. Tap a muscle for its own count.
class MuscleSection extends StatefulWidget {
  const MuscleSection({super.key});

  @override
  State<MuscleSection> createState() => _MuscleSectionState();
}

class _MuscleSectionState extends State<MuscleSection> {
  static const _windows = [Segment(7, 'Semana'), Segment(30, '30 d'), Segment(90, '90 d'), Segment(0, 'Todo')];
  static const _top = 4;

  int _window = 7;
  bool _hard = false;
  bool _showAll = false;
  String? _selected;

  /// Every change of window or mode clears the selection.
  void _set(VoidCallback change) => setState(() {
    change();
    _selected = null;
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.workouts.isEmpty) {
      return const EmptyState(
        icon: 'figureStrength',
        message: 'Termina tu primer entrenamiento para ver qué músculos trabajas y cuáles se quedan sin trabajo.',
      );
    }
    final p = context.palette;
    final inWindow = muscleBalanceWorkouts(app.workouts, _window, now: app.clock.now());
    final rated = hasHardSets(inWindow);
    final hard = _hard && rated;
    final load = loadOfWorkouts(app.exerciseIndex, inWindow, pick: hard ? isHardSet : null);
    final rank = rankOf(load);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeading(
            'Equilibrio muscular',
            detail: hard ? 'por series duras' : 'por series trabajadas',
            trailing: [
              if (rated)
                AppButton(
                  hard ? 'Duras' : 'Todas',
                  icon: 'flame',
                  size: ButtonSize.sm,
                  foreground: hard ? p.yellow : null,
                  onPressed: () => _set(() => _hard = !_hard),
                ),
            ],
          ),
          Segmented(segments: _windows, value: _window, onChanged: (v) => _set(() => _window = v)),
          const SizedBox(height: 12),
          if (inWindow.isEmpty)
            Text('Aún no hay entrenamientos en este periodo.', style: context.textStyles.small)
          else ...[
            BodyMap(
              levels: levelsOf(load),
              figure: app.settings.body,
              highlight: _selected == null ? null : {_selected!},
              onMuscle: (m) => setState(() => _selected = _selected == m ? null : m),
            ),
            const BodyMapLegend(),
            const SizedBox(height: 6),
            ..._details(context, load, rank, hard),
          ],
        ],
      ),
    );
  }

  List<Widget> _details(
    BuildContext context,
    MuscleLoad load,
    ({List<String> worked, List<String> missed}) rank,
    bool hard,
  ) {
    final p = context.palette;
    String sets(String m) => '${fmtNum(round1(load[m] ?? 0))} series';
    final selected = _selected;
    final worked = rank.worked, missed = rank.missed;
    final max = worked.isEmpty ? 1 : math.max(load[worked.first]!, 1e-9);
    final shown = _showAll ? worked : worked.take(_top).toList();
    return [
      if (selected != null)
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.sep, width: .5)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MetricBarRow(
              label: muscleNames[selected] ?? selected,
              bold: true,
              value: (load[selected] ?? 0) > 0 ? sets(selected) : (hard ? 'sin series duras' : 'sin entrenar'),
            ),
          ),
        )
      else ...[
        for (final m in shown)
          MetricBarRow(
            label: muscleNames[m] ?? m,
            fraction: load[m]! / max,
            color: hard ? p.yellow : null,
            value: sets(m),
          ),
        if (worked.length > _top)
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              _showAll ? 'Mostrar menos' : 'Ver los ${worked.length}',
              size: ButtonSize.xs,
              trailingIcon: _showAll ? 'chevronUp' : 'chevronDown',
              onPressed: () => setState(() => _showAll = !_showAll),
            ),
          ),
      ],
      if (missed.isNotEmpty) ...[
        CardCaption(hard ? 'Sin series duras en este periodo' : 'Sin entrenar en este periodo'),
        ChipWrap(children: [for (final m in missed) MuscleChip(m, missed: true)]),
      ] else if (worked.isNotEmpty)
        NoteText(
          hard
              ? 'Todos los grupos musculares recibieron al menos una serie dura en este periodo.'
              : 'Todos los grupos musculares recibieron algo de trabajo en este periodo.',
          color: p.label2,
        ),
    ];
  }
}
