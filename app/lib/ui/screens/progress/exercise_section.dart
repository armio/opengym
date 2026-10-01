import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'progress_data.dart';
import 'progress_widgets.dart';
import 'trend_chart.dart';

/// "Ejercicios" (specs/ui.md §3.6 "Exercise progress"): pick an exercise from the ones logged,
/// then its top-set / estimated-1RM / effort curve, the last five sessions, its records and,
/// for reps exercises, an estimated-1RM calculator.
class ExerciseSection extends StatefulWidget {
  const ExerciseSection({super.key});

  @override
  State<ExerciseSection> createState() => _ExerciseSectionState();
}

class _ExerciseSectionState extends State<ExerciseSection> {
  String? _exId;
  ExerciseMetric _metric = ExerciseMetric.top;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final state = app.trainingState;
    final ids = progressExercises(state);
    if (ids.isEmpty) {
      return const EmptyState(
        icon: 'chartLine',
        message: 'Termina tu primer entrenamiento para ver curvas de progreso aquí.',
      );
    }
    final exId = ids.contains(_exId) ? _exId! : ids.first;
    final progress = ExerciseProgress.of(state, exId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          children: [
            SelectRow<String>(
              title: 'Ejercicio',
              sheetTitle: 'Progreso por ejercicio',
              value: exId,
              options: [for (final id in ids) SelectOption(id, capitalizeWords(state.catalog.nameOf(id)))],
              onChanged: (id) => setState(() => _exId = id),
            ),
          ],
        ),
        AppCard(
          child: _ProgressChart(
            progress: progress,
            metric: progress.resolve(_metric),
            onMetric: (m) => setState(() => _metric = m),
          ),
        ),
        _Records(progress: progress),
        if (progress.mode == ExerciseMode.reps)
          AppCard(
            child: OneRepMaxCalculator(key: ValueKey(exId), exId: exId),
          ),
      ],
    );
  }
}

class _ProgressChart extends StatelessWidget {
  const _ProgressChart({required this.progress, required this.metric, required this.onMetric});

  final ExerciseProgress progress;
  final ExerciseMetric metric;
  final ValueChanged<ExerciseMetric> onMetric;

  static const _labels = {
    ExerciseMetric.top: 'Mejor serie',
    ExerciseMetric.e1rm: '1RM est.',
    ExerciseMetric.effort: 'Esfuerzo',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.palette;
    final unit = app.settings.unit;
    final kind = displayScale(app.settings, app.workouts);
    final hd = scaleName(kind);
    final metrics = progress.metrics;
    final chart = switch (metric) {
      ExerciseMetric.effort => TrendChart(
        points: progress.effortPoints(kind),
        unit: hd,
        color: p.yellow,
        invert: kind == 'rir',
      ),
      ExerciseMetric.e1rm => TrendChart(points: progress.e1rmPoints, unit: unit, color: p.blue),
      ExerciseMetric.top => TrendChart(points: progress.topPoints(kind), unit: progress.unitFor(unit), color: p.blue),
    };
    final recent = progress.recent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.length > 1) ...[
          Segmented<ExerciseMetric>(
            segments: [for (final m in metrics) Segment(m, _labels[m]!)],
            value: metric,
            onChanged: onMetric,
          ),
          const SizedBox(height: 10),
        ],
        chart,
        const SizedBox(height: 8),
        for (var i = 0; i < recent.length; i++)
          HairlineRow(
            leading: fmtDate(recent[i].d, long: true),
            trailing: _setsLine(app, recent[i]),
            last: i == recent.length - 1,
          ),
        _caption(context, unit, hd),
        ..._notes(unit, hd),
      ],
    );
  }

  String _setsLine(AppState app, ProgressPoint point) {
    final target = point.target;
    final cfg = target == null ? null : RoutineExercise.fromJson({...target, 'id': target['id'] ?? progress.exId});
    return joinSetLabels(point.sets.map((s) => setLabel(app.exerciseIndex, progress.exId, s, cfg)));
  }

  Widget _caption(BuildContext context, String unit, String hd) {
    final p = context.palette;
    final text = switch (metric) {
      ExerciseMetric.effort => 'Esfuerzo medio por entrenamiento',
      ExerciseMetric.e1rm => '1RM estimado por entrenamiento',
      ExerciseMetric.top => switch (progress.mode) {
        ExerciseMode.cardio => 'Velocidad máxima por entrenamiento',
        ExerciseMode.time => 'Isométrico más largo por entrenamiento',
        _ => 'Mejor peso por entrenamiento',
      },
    };
    final best = switch (metric) {
      ExerciseMetric.effort => null,
      ExerciseMetric.e1rm => fmtVol(progress.best1rm?.est ?? 0, unit),
      ExerciseMetric.top => '${fmtNum(progress.bestTop)} ${progress.unitFor(unit)}',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (best != null) ...[
              const TextSpan(text: ' · Mejor: '),
              TextSpan(
                text: best,
                style: TextStyle(color: p.acc, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        style: context.textStyles.small.copyWith(color: p.label3),
      ),
    );
  }

  List<Widget> _notes(String unit, String hd) {
    final best = progress.best1rm;
    if (metric == ExerciseMetric.e1rm && best != null) {
      return [
        NoteText(
          'Mejor estimación a partir de ${fmtVol(best.w, unit)} × ${fmtNum(best.r)} el ${fmtDate(best.d, long: true)}: '
          'una estimación, no un máximo probado.',
          top: 4,
        ),
      ];
    }
    if (metric == ExerciseMetric.top && progress.hasEffort) {
      return [
        NoteText(
          'Un punto más lleno significa menos reserva — el mismo peso con un $hd más bajo es progreso que la '
          'línea por sí sola no muestra.',
          top: 4,
        ),
      ];
    }
    return const [];
  }
}

/// The exercise's records: best load and best estimated 1RM with the set behind it (reps),
/// longest hold (time) or top speed (cardio), and how often and when it was last trained.
class _Records extends StatelessWidget {
  const _Records({required this.progress});

  final ExerciseProgress progress;

  @override
  Widget build(BuildContext context) {
    final unit = context.select<AppState, String>((s) => s.settings.unit);
    final best = progress.best1rm;
    final last = progress.sessions.isEmpty ? null : progress.sessions.last;
    return Section(
      title: 'Récords',
      children: [
        ...switch (progress.mode) {
          ExerciseMode.cardio => [
            ListRow(icon: 'bolt', title: 'Velocidad máxima', value: '${fmtNum(progress.bestTop)} km/h'),
          ],
          ExerciseMode.time => [ListRow(icon: 'timer', title: 'Isométrico más largo', value: fmtSec(progress.bestTop))],
          _ => [
            ListRow(
              icon: 'trophy',
              title: 'Mejor carga',
              value: progress.bestLoad > 0 ? fmtVol(progress.bestLoad, unit) : '—',
            ),
            ListRow(
              icon: 'chartLine',
              title: 'Mejor 1RM estimado',
              subtitle: best == null
                  ? 'Solo series de 1 a $repCap repeticiones'
                  : '${fmtVol(best.w, unit)} × ${fmtNum(best.r)} · ${fmtDate(best.d, long: true)}',
              value: best == null ? '—' : fmtVol(best.est, unit),
            ),
          ],
        },
        ListRow(icon: 'history', title: 'Sesiones', value: '${progress.sessions.length}'),
        if (last != null) ListRow(icon: 'calendar', title: 'Última sesión', value: fmtDate(last.d, long: true)),
      ],
    );
  }
}

/// "Calculadora de 1RM": Epley from a weight × reps (1–12 reps), seeded with the set behind the
/// best estimate, else the working weight × 5.
class OneRepMaxCalculator extends StatefulWidget {
  const OneRepMaxCalculator({super.key, required this.exId});

  final String exId;

  @override
  State<OneRepMaxCalculator> createState() => _OneRepMaxCalculatorState();
}

class _OneRepMaxCalculatorState extends State<OneRepMaxCalculator> {
  late num? _weight;
  late num? _reps;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final best = best1RM(app.workouts, widget.exId);
    _weight = best?.w ?? app.exWeights[widget.exId]?.w ?? 20;
    _reps = best?.r ?? 5;
  }

  @override
  Widget build(BuildContext context) {
    final unit = context.select<AppState, String>((s) => s.settings.unit);
    final estimate = estimate1RM(_weight, _reps);
    final p = context.palette;
    final t = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CardHeading('Calculadora de 1RM'),
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('1RM estimado', style: t.small.copyWith(color: p.label)),
            ),
            Text(
              estimate == null ? '—' : fmtVol(estimate, unit),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.acc),
            ),
          ],
        ),
        NoteText(
          estimate == null
              ? 'Introduce un peso y de 1 a $repCap repeticiones: más allá, la estimación es adivinar.'
              : 'Fórmula de Epley: un cálculo a partir de una serie, no un máximo probado.',
          top: 4,
        ),
      ],
    );
  }
}
