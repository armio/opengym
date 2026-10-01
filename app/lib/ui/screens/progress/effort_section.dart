import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'progress_data.dart';
import 'progress_widgets.dart';
import 'trend_chart.dart';

/// "Esfuerzo" (specs/ui.md §3.6 "Effort", engine.md §6): how close to failure the training was,
/// in the owner's scale — average effort, share of hard sets, week by week and a histogram.
/// Every number says how much of the training it speaks for, since rating is optional. Shown
/// only when some set carries a rating.
class EffortSection extends StatefulWidget {
  const EffortSection({super.key});

  @override
  State<EffortSection> createState() => _EffortSectionState();
}

class _EffortSectionState extends State<EffortSection> {
  static const _windows = [Segment(30, '30 d'), Segment(90, '90 d'), Segment(365, '1 año'), Segment(0, 'Todo')];

  int _window = 90;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final workouts = app.workouts;
    final now = app.clock.now();
    final kind = displayScale(app.settings, workouts);
    final summary = effortSummary(workouts, _window, now: now);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeading('Esfuerzo', detail: 'qué tan cerca del fallo'),
          Segmented(segments: _windows, value: _window, onChanged: (v) => setState(() => _window = v)),
          const SizedBox(height: 12),
          if (summary.rated == 0)
            Text('Ninguna serie valorada en este periodo.', style: context.textStyles.small)
          else
            _EffortBody(
              kind: kind,
              summary: summary,
              weeks: effortWeeks(workouts, _window, now: now),
              histogram: effortHistogram(workouts, _window, now: now),
              switchedOff: effortOf(app.settings) == 'none',
            ),
        ],
      ),
    );
  }
}

class _EffortBody extends StatelessWidget {
  const _EffortBody({
    required this.kind,
    required this.summary,
    required this.weeks,
    required this.histogram,
    required this.switchedOff,
  });

  final String kind;
  final EffortSummary summary;
  final List<EffortWeek> weeks;
  final List<EffortBin> histogram;
  final bool switchedOff;

  /// Bins run hardest-first in both scales: RIR 0 and RPE 10 are the same set.
  String _binLabel(EffortBin b) =>
      kind == 'rpe' ? (b.tail ? '≤ 6' : '${10 - b.rir}') : (b.tail ? '${b.rir}+' : '${b.rir}');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hd = scaleName(kind);
    final avg = summary.avg, hardPct = summary.hardPct;
    final maxBin = histogram.fold<int>(1, (a, b) => math.max(a, b.n));
    // The week's set count rides along in the tooltip: volume up with effort up is fatigue
    // piling up, volume up with effort flat is adaptation.
    final points = [
      for (final w in weeks)
        ChartPoint(t: w.t, y: toScale(kind, w.rir)!, note: w.sets == 1 ? '1 serie' : '${w.sets} series'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: StatValue(
                value: avg == null ? '—' : '${fmtNum(toScale(kind, avg)!)} $hd',
                caption: 'esfuerzo medio',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatValue(
                value: hardPct == null ? '—' : '${(hardPct * 100).round()}%',
                caption: 'a $hd ${fmtNum(toScale(kind, hardRir)!)} o más duro',
                color: p.yellow,
                align: TextAlign.right,
              ),
            ),
          ],
        ),
        NoteText('${summary.rated} de ${summary.done} series completadas valoradas'),
        if (switchedOff)
          NoteText(
            'El esfuerzo por serie está desactivado — actívalo en Ajustes para seguir valorando.',
            color: p.yellow,
            top: 4,
          ),
        if (points.length > 1) ...[
          const CardCaption('Semana a semana'),
          TrendChart(points: points, height: 140, unit: hd, color: p.yellow, invert: kind == 'rir'),
        ],
        const CardCaption('Dónde caen las series'),
        for (final b in histogram)
          MetricBarRow(
            label: '$hd ${_binLabel(b)}',
            fraction: b.n / maxBin,
            color: b.rir <= hardRir ? p.yellow : p.label3,
            value: b.n == 0 ? '—' : '${b.n} · ${(b.pct * 100).round()}%',
          ),
        const NoteText(
          'La mayoría de las series efectivas van cerca del fallo sin vivir allí — la mitad abajo y la mitad '
          'arriba dan una media que solo parece sana.',
        ),
      ],
    );
  }
}
