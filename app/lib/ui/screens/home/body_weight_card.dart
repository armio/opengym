import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../progress/progress_data.dart' show ChartPoint;
import '../progress/trend_chart.dart';

/// "Peso corporal" (specs/ui.md §3.2): the latest weigh-in with its change since the previous
/// one (accent towards the goal, red away from it), the goal and how far it is, and the curve of
/// the last 30 weigh-ins. "Meta" sets the goal, "Registrar" logs today's weight.
class BodyWeightCard extends StatelessWidget {
  const BodyWeightCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final entries = app.bodyWeights;
    final unit = app.settings.unit;
    final goal = app.settings.targetW;
    final latest = entries.isEmpty ? null : entries.last;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(goal: goal),
          if (latest == null)
            Text(
              'Sin registros aún — apunta tu peso para empezar la curva. También se pide antes de cada entrenamiento.',
              style: context.textStyles.small,
            )
          else ...[
            _Latest(latest: latest, previous: entries.length > 1 ? entries[entries.length - 2] : null, goal: goal),
            if (goal != null) _GoalLine(goal: goal, current: latest.w, unit: unit),
            const SizedBox(height: 8),
            TrendChart(
              height: 130,
              unit: unit,
              goal: goal,
              points: [
                for (final b in entries.skip(entries.length > 30 ? entries.length - 30 : 0))
                  ChartPoint(t: weighInTime(b), y: b.w, d: b.d),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.goal});

  final num? goal;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text('Peso corporal', style: context.textStyles.caption)),
          AppButton(
            goal == null ? 'Meta' : formatNum(goal!),
            icon: 'target',
            size: ButtonSize.sm,
            foreground: goal == null ? null : p.yellow,
            onPressed: () => showGoalSheet(context),
          ),
          AppButton('Registrar', icon: 'plus', size: ButtonSize.sm, onPressed: () => showBodyWeightSheet(context)),
        ],
      ),
    );
  }
}

class _Latest extends StatelessWidget {
  const _Latest({required this.latest, required this.previous, required this.goal});

  final BodyWeight latest;
  final BodyWeight? previous;
  final num? goal;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final unit = context.select<AppState, String>((s) => s.settings.unit);
    final delta = previous == null ? 0 : round1(latest.w - previous!.w);
    final deltaColor = bodyWeightDeltaColor(context, delta, latest.w, goal);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text.rich(
          TextSpan(
            text: formatNum(latest.w),
            children: [
              TextSpan(
                text: ' $unit',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: p.label2),
              ),
            ],
          ),
          style: t.bigNumber,
        ),
        // Only when it actually moved — an unchanged weight would read as "− 0".
        if (delta != 0) ...[
          const SizedBox(width: 8),
          AppIcon(delta > 0 ? 'arrowUp' : 'arrowDown', size: 12, color: deltaColor),
          const SizedBox(width: 2),
          Text(
            formatNum(delta.abs()),
            style: t.small.copyWith(color: deltaColor, fontWeight: FontWeight.w500),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            formatDate(latest.d, long: true),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.small.copyWith(color: p.label3),
          ),
        ),
      ],
    );
  }
}

/// "Meta 75 kg · 3,5 kg por perder" (or "¡conseguido!").
class _GoalLine extends StatelessWidget {
  const _GoalLine({required this.goal, required this.current, required this.unit});

  final num goal;
  final num current;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final yellow = context.palette.yellow;
    final diff = (goal - current).abs();
    final status = diff < 0.05
        ? '¡conseguido!'
        : goal > current
        ? '${formatWeight(diff, unit)} por ganar'
        : '${formatWeight(diff, unit)} por perder';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          AppIcon('target', size: 13, color: yellow),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Meta ${formatWeight(goal, unit)} · $status',
              style: context.textStyles.small.copyWith(color: yellow),
            ),
          ),
        ],
      ),
    );
  }
}
