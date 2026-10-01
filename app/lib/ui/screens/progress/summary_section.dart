import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/dates.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'history_screen.dart';
import 'progress_data.dart';
import 'progress_widgets.dart';
import 'workout_row.dart';

/// "Resumen": the stats tiles (specs/ui.md §3.6) plus total volume and time, workouts per week
/// against the plan, and the last six workouts with the way into the full history.
class SummarySection extends StatelessWidget {
  const SummarySection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final workouts = app.workouts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Tiles(),
        if (workouts.isEmpty)
          const EmptyState(icon: 'chart', message: 'Termina tu primer entrenamiento para ver tu progreso aquí.')
        else ...[
          AppCard(
            child: _WeeklyWorkouts(
              weeks: weeklyCounts(workouts, now: app.clock.now()),
              planned: plannedPerWeek(app.plan),
            ),
          ),
          SectionCaption(
            'Entrenamientos recientes',
            trailing: AppButton(
              'Todos ${workouts.length}',
              size: ButtonSize.sm,
              variant: ButtonVariant.ghost,
              trailingIcon: 'chevronRight',
              onPressed: () => HistoryScreen.open(context),
            ),
          ),
          ItemList(
            children: [for (final w in recentWorkouts(workouts)) WorkoutRow(key: ValueKey(w.id), workout: w)],
          ),
        ],
      ],
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = context.textStyles;
    final p = context.palette;
    final unit = app.settings.unit;
    final tiles = statsTiles(app.workouts, app.bodyWeights, now: app.clock.now());
    final change = tiles.weightChange30d;
    final small = t.statValue.copyWith(fontSize: 22);
    return TilePairs(
      tiles: [
        StatTile(icon: 'dumbbell', label: 'Entrenos', value: '${tiles.workouts}'),
        StatTile(icon: 'calendar', label: 'Este mes', value: '${tiles.thisMonth}'),
        StatTile(icon: 'flame', label: 'Racha semanal', value: '${tiles.streakWeeks}'),
        StatTile(
          icon: 'scale',
          label: 'Peso 30 d',
          value: change == null ? '—' : '${change > 0 ? '+' : ''}${fmtVol(change, unit)}',
          valueStyle: small.copyWith(
            color: change == null
                ? p.label
                : bodyWeightDeltaColor(context, change, app.lastBodyWeight?.w ?? 0, app.settings.targetW),
          ),
        ),
        StatTile(
          icon: 'barbell',
          label: 'Volumen total',
          value: fmtVol(totalVolume(app.workouts), unit),
          valueStyle: small,
        ),
        StatTile(icon: 'clock', label: 'Tiempo total', value: fmtDur(totalDuration(app.workouts)), valueStyle: small),
      ],
    );
  }
}

/// Bars of workouts per ISO week, the current week in full accent, with the plan's weekly
/// target as a dashed line.
class _WeeklyWorkouts extends StatelessWidget {
  const _WeeklyWorkouts({required this.weeks, required this.planned});

  final List<WeekCount> weeks;

  /// Training days in the weekly plan (0 = none).
  final int planned;

  static const double _barArea = 72;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = math.max(planned, weeks.fold<int>(1, (a, w) => math.max(a, w.count)));
    final average = weeks.fold<int>(0, (a, w) => a + w.count) / weeks.length;
    final note = [
      'Media: ${fmtNum(average)} por semana',
      if (planned > 0) 'tu plan: $planned ${planned == 1 ? 'día' : 'días'}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardHeading('Entrenos por semana', detail: 'últimas ${weeks.length} semanas'),
        SizedBox(
          height: _barArea + 20,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < weeks.length; i++)
                    Expanded(
                      child: _Bar(
                        count: weeks[i].count,
                        fraction: weeks[i].count / top,
                        current: i == weeks.length - 1,
                        height: _barArea,
                      ),
                    ),
                ],
              ),
              if (planned > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: planned / top * _barArea,
                  child: CustomPaint(painter: _DashPainter(p.yellow), size: const Size.fromHeight(1.4)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final w in weeks)
              Expanded(
                child: Text(
                  _monthLabel(w.monday),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(fontSize: 10, color: p.label3),
                ),
              ),
          ],
        ),
        NoteText(note),
      ],
    );
  }

  /// The month's abbreviation under its first week.
  static String _monthLabel(String monday) {
    final d = parseIsoDate(monday);
    return d != null && d.day <= 7 ? monthNamesShort[d.month - 1] : '';
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.count, required this.fraction, required this.current, required this.height});

  final int count;
  final double fraction;
  final bool current;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (count > 0) Text('$count', style: TextStyle(fontSize: 11, color: current ? p.label : p.label2)),
          const SizedBox(height: 3),
          Container(
            height: count == 0 ? 2 : math.max(4, fraction * height),
            decoration: BoxDecoration(
              color: count == 0 ? p.surface3 : (current ? p.acc : p.acc.withValues(alpha: .55)),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    for (var x = 0.0; x < size.width; x += 11) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 7, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
