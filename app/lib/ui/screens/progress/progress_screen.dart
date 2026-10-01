import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'activity_section.dart';
import 'body_weight_section.dart';
import 'effort_section.dart';
import 'exercise_section.dart';
import 'history_screen.dart';
import 'muscle_section.dart';
import 'summary_section.dart';

export 'activity_section.dart' show ActivityHeatmap, HeatmapCell;
export 'history_screen.dart' show HistoryScreen;
export 'trend_chart.dart' show ChartEmpty, TrendChart;
export 'workout_detail_sheet.dart' show showWorkoutDetailSheet;
export 'workout_row.dart' show WorkoutRow;

/// The parts of the Progress tab, one shown at a time.
enum ProgressSection {
  summary('Resumen'),
  bodyWeight('Peso corporal'),
  activity('Actividad'),
  exercises('Ejercicios'),
  effort('Esfuerzo'),
  muscles('Músculos');

  const ProgressSection(this.label);

  final String label;
}

/// The Progreso tab (specs/ui.md §3.6–3.7): stats split into sections — summary, body weight,
/// activity, exercise progress, effort (only once some set carries a rating) and muscle
/// balance — with the full history one tap away.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.initialSection = ProgressSection.summary});

  final ProgressSection initialSection;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late ProgressSection _section = widget.initialSection;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sections = [
      for (final s in ProgressSection.values)
        if (s != ProgressSection.effort || hasEffort(app.workouts)) s,
    ];
    final section = sections.contains(_section) ? _section : ProgressSection.summary;
    final navigator = Navigator.of(context);
    return Scaffold(
      body: PageBody(
        onRefresh: app.sync,
        children: [
          ScreenHeader(
            title: 'Progreso',
            subtitle: 'Progreso e historial',
            leading: navigator.canPop()
                ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: navigator.pop)
                : null,
            actions: [
              AppIconButton(icon: 'history', tooltip: 'Historial', onPressed: () => HistoryScreen.open(context)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ChipsRow(
              children: [
                for (final s in sections)
                  Builder(
                    builder: (chipContext) => AppChip(
                      s.label,
                      selected: s == section,
                      capitalize: false,
                      onTap: () => _select(chipContext, s),
                    ),
                  ),
              ],
            ),
          ),
          KeyedSubtree(key: ValueKey(section), child: _body(section)),
        ],
      ),
    );
  }

  /// Shows [section] and slides its chip into view — only the chip row scrolls, not the page.
  void _select(BuildContext chipContext, ProgressSection section) {
    setState(() => _section = section);
    final chip = chipContext.findRenderObject();
    if (chip == null) return;
    Scrollable.maybeOf(chipContext)?.position.ensureVisible(
      chip,
      alignment: .5,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.med,
      curve: AppMotion.ease,
    );
  }

  Widget _body(ProgressSection section) => switch (section) {
    ProgressSection.summary => const SummarySection(),
    ProgressSection.bodyWeight => const BodyWeightSection(),
    ProgressSection.activity => const ActivitySection(),
    ProgressSection.exercises => const ExerciseSection(),
    ProgressSection.effort => const EffortSection(),
    ProgressSection.muscles => const MuscleSection(),
  };
}
