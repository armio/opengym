import 'dart:math' as math;

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

/// "Peso corporal" (specs/ui.md §3.6): the goal and log buttons, a 1M / 3M / 1A / Todo range
/// (default 3M), the weight curve with the goal line, the change over the range coloured towards
/// or away from the goal, and the log of weigh-ins (tap one to correct or delete it).
class BodyWeightSection extends StatefulWidget {
  const BodyWeightSection({super.key});

  @override
  State<BodyWeightSection> createState() => _BodyWeightSectionState();
}

class _BodyWeightSectionState extends State<BodyWeightSection> {
  static const _ranges = [Segment(30, '1M'), Segment(90, '3M'), Segment(365, '1A'), Segment(0, 'Todo')];
  static const _page = 10;

  int _range = 90;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final unit = app.settings.unit;
    final points = bodyWeightPoints(app.bodyWeights, _range, now: app.clock.now());
    final log = weighInLog(app.bodyWeights);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              Segmented(segments: _ranges, value: _range, onChanged: (v) => setState(() => _range = v)),
              const SizedBox(height: 10),
              TrendChart(points: points, height: 160, unit: unit, goal: app.settings.targetW),
              _RangeSummary(points: points),
            ],
          ),
        ),
        if (log.isEmpty)
          const EmptyState(icon: 'scale', message: 'Aún no hay pesajes. Registra tu peso para ver tu curva.')
        else
          Section(
            title: 'Pesajes',
            footer: log.length > _shown ? null : '${log.length} ${log.length == 1 ? 'pesaje' : 'pesajes'}',
            children: [
              for (final w in log.take(_shown)) _WeighInRow(weighIn: w),
              if (log.length > _shown)
                ListRow(
                  title: 'Mostrar más',
                  value: '${log.length - _shown}',
                  onTap: () => setState(() => _shown += 20),
                ),
            ],
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final goal = context.select<AppState, num?>((s) => s.settings.targetW);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text('Peso corporal', style: context.textStyles.caption)),
          AppButton(
            goal == null ? 'Meta' : fmtNum(goal),
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

/// The latest weigh-in, the change over the range and the distance to the goal.
class _RangeSummary extends StatelessWidget {
  const _RangeSummary({required this.points});

  final List<ChartPoint> points;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final unit = app.settings.unit;
    final goal = app.settings.targetW;
    final latest = app.lastBodyWeight;
    if (latest == null) return const SizedBox.shrink();
    final change = weightChange(points);
    final p = context.palette;
    final changeText = change == null ? '—' : '${change > 0 ? '+' : ''}${fmtVol(change, unit)}';
    final changeColor = change == null ? p.label2 : bodyWeightDeltaColor(context, change, latest.w, goal);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: StatValue(value: fmtVol(latest.w, unit), caption: 'Último · ${fmtDate(latest.d)}', fontSize: 22),
          ),
          Expanded(
            child: StatValue(
              value: changeText,
              caption: 'En el periodo',
              color: changeColor,
              align: goal == null ? TextAlign.right : TextAlign.center,
              fontSize: 22,
            ),
          ),
          if (goal != null)
            Expanded(
              child: StatValue(
                value: fmtVol(round1((goal - latest.w).abs()), unit),
                caption: 'Hasta la meta',
                color: p.yellow,
                align: TextAlign.right,
                fontSize: 22,
              ),
            ),
        ],
      ),
    );
  }
}

/// One weigh-in: date, weight and the change since the previous one.
class _WeighInRow extends StatelessWidget implements GroupedRow {
  const _WeighInRow({required this.weighIn});

  final WeighIn weighIn;

  @override
  bool get hasIcon => false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final unit = app.settings.unit;
    final p = context.palette;
    final t = context.textStyles;
    final change = weighIn.change;
    final entry = weighIn.entry;
    return Pressable(
      onTap: () => _showEditWeighIn(context, entry),
      pressedScale: 1,
      color: Colors.transparent,
      pressedColor: p.surface2,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Expanded(child: Text(fmtDate(entry.d, long: true), style: t.rowTitle)),
              if (change != null && change != 0)
                Text(
                  '${change > 0 ? '+' : ''}${fmtNum(change)}',
                  style: t.caption.copyWith(
                    color: bodyWeightDeltaColor(context, change, entry.w, app.settings.targetW),
                  ),
                ),
              const SizedBox(width: 10),
              Text(fmtVol(entry.w, unit), style: t.rowTitle.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              AppIcon('chevronRight', size: 18, color: p.label3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Corrects or deletes one weigh-in (its date and entry time are kept).
Future<void> _showEditWeighIn(BuildContext context, BodyWeight entry) =>
    showAppSheet<void>(context, builder: (_) => _EditWeighIn(entry: entry));

class _EditWeighIn extends StatefulWidget {
  const _EditWeighIn({required this.entry});

  final BodyWeight entry;

  @override
  State<_EditWeighIn> createState() => _EditWeighInState();
}

class _EditWeighInState extends State<_EditWeighIn> {
  late num _value = widget.entry.w;

  void _save() {
    final app = context.read<AppState>();
    final w = roundWeight(math.max(_value, 0));
    if (w <= 0) {
      showToast(context, 'Introduce un peso válido');
      return;
    }
    app.setBodyWeight(w, date: widget.entry.d, t: widget.entry.t);
    showToast(context, 'Peso guardado');
    Navigator.of(context).pop();
  }

  void _delete() {
    context.read<AppState>().deleteBodyWeight(widget.entry.d);
    showToast(context, 'Pesaje borrado');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final unit = context.select<AppState, String>((s) => s.settings.unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle('Editar pesaje'),
        Text(capitalizeFirst(fmtDate(widget.entry.d, long: true)), style: context.textStyles.small),
        WeightInput(value: _value, unit: unit, onChanged: (v) => setState(() => _value = v)),
        const SizedBox(height: 14),
        AppButton('Guardar', variant: ButtonVariant.primary, onPressed: _save),
        const SizedBox(height: 8),
        AppButton('Borrar pesaje', icon: 'trash', variant: ButtonVariant.danger, onPressed: _delete),
      ],
    );
  }
}
