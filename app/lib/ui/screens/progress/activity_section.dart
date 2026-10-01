import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../plan/calendar_sheet.dart' show showCalendarSheet;
import 'progress_data.dart';
import 'progress_widgets.dart';
import 'workout_detail_sheet.dart';

/// "Actividad": the last 12 months as a heatmap shaded by minutes trained (specs/ui.md §7.2)
/// and the last months' totals. A day with one workout opens it; a day with several, or a
/// month, opens the Plan calendar there.
class ActivitySection extends StatelessWidget {
  const ActivitySection({super.key});

  static Future<void> _openCalendar(BuildContext context, [String? iso]) =>
      showCalendarSheet(context, startIso: iso, openWorkout: showWorkoutDetailSheet);

  static void _onDay(BuildContext context, String iso) {
    final workouts = context.read<AppState>().workouts.where((w) => w.d == iso).toList();
    if (workouts.length == 1) {
      showWorkoutDetailSheet(context, workouts.single);
    } else if (workouts.isNotEmpty) {
      _openCalendar(context, iso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = app.clock.now();
    final grid = heatmapGrid(now: now);
    final days = heatmapDays(app.workouts);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardHeading(
                'Actividad — últimos 12 meses',
                detail: 'por tiempo entrenado',
                trailing: [
                  AppIconButton(
                    icon: 'calendar',
                    tooltip: 'Calendario',
                    size: 32,
                    iconSize: 16,
                    background: p.surface2,
                    onPressed: () => _openCalendar(context),
                  ),
                ],
              ),
              ActivityHeatmap(grid: grid, days: days, onDay: (iso) => _onDay(context, iso)),
              NoteText(_yearSummary(grid, days)),
            ],
          ),
        ),
        _MonthTotals(workouts: app.workouts, today: grid.today, onMonth: (iso) => _openCalendar(context, iso)),
      ],
    );
  }

  static String _yearSummary(HeatmapGrid grid, Map<String, HeatmapDay> days) {
    var trained = 0, minutes = 0;
    for (final week in grid.weeks) {
      for (final iso in week) {
        final day = days[iso];
        if (day == null) continue;
        trained++;
        minutes += day.minutes;
      }
    }
    if (trained == 0) return 'Aún no hay entrenamientos en los últimos 12 meses.';
    final dayText = trained == 1 ? '1 día entrenado' : '$trained días entrenados';
    return '$dayText · ${fmtDur(minutes * 60000)} en total';
  }
}

/// The GitHub-style grid: 53 Monday-first columns, oldest left, scrolled to today at first;
/// month labels on top, Lun / Mié / Vie on the left and the "Menos … Más" key below.
class ActivityHeatmap extends StatefulWidget {
  const ActivityHeatmap({super.key, required this.grid, required this.days, required this.onDay});

  final HeatmapGrid grid;
  final Map<String, HeatmapDay> days;

  /// Called for a tapped day that has workouts.
  final ValueChanged<String> onDay;

  static const double cell = 11;
  static const double gap = 3;

  @override
  State<ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<ActivityHeatmap> {
  final _scroll = ScrollController();

  static const _pitch = ActivityHeatmap.cell + ActivityHeatmap.gap;
  static const _dayLabels = ['Lun', '', 'Mié', '', 'Vie', '', ''];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scale = HeatmapScale.of(widget.days);
    final grid = widget.grid;
    final monthStyle = TextStyle(fontSize: 11, color: p.label3, height: 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                width: 28,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final label in _dayLabels)
                      SizedBox(
                        height: _pitch,
                        child: Text(label, style: TextStyle(fontSize: 10, color: p.label2, height: 1.1)),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 16,
                      child: Row(
                        children: [
                          for (final month in grid.monthLabels)
                            SizedBox(
                              width: _pitch,
                              child: Text(
                                month == null ? '' : monthNamesShort[month - 1],
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: monthStyle,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final week in grid.weeks) _column(week, scale)],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _HeatLegend(),
      ],
    );
  }

  Widget _column(List<String> week, HeatmapScale scale) => Padding(
    padding: const EdgeInsets.only(right: ActivityHeatmap.gap),
    child: Column(
      children: [
        for (final iso in week)
          Padding(
            padding: const EdgeInsets.only(bottom: ActivityHeatmap.gap),
            child: HeatmapCell(
              key: ValueKey('heat-$iso'),
              iso: iso,
              day: widget.days[iso],
              level: scale.levelOf(widget.days[iso]),
              future: widget.grid.isFuture(iso),
              today: iso == widget.grid.today,
              onTap: widget.days.containsKey(iso) ? () => widget.onDay(iso) : null,
            ),
          ),
      ],
    ),
  );
}

/// One day of the heatmap, shaded by its [level] (0–4) of the heat ramp.
class HeatmapCell extends StatelessWidget {
  const HeatmapCell({
    super.key,
    required this.iso,
    required this.level,
    this.day,
    this.future = false,
    this.today = false,
    this.onTap,
  });

  final String iso;
  final int level;
  final HeatmapDay? day;
  final bool future;
  final bool today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final box = Container(
      width: ActivityHeatmap.cell,
      height: ActivityHeatmap.cell,
      decoration: BoxDecoration(
        color: p.heatCell(level),
        borderRadius: BorderRadius.circular(3),
        border: today ? Border.all(color: p.acc, width: 1.5) : null,
      ),
    );
    final d = day;
    return Semantics(
      label: d == null ? iso : '$iso · ${workoutCount(d.workouts)} · ${d.minutes} min',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(opacity: future ? .3 : 1, child: box),
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(fontSize: 11, color: p.label3);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Menos', style: style),
        for (var l = 0; l <= 4; l++) ...[
          const SizedBox(width: 4),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: p.heatCell(l), borderRadius: BorderRadius.circular(3)),
          ),
        ],
        const SizedBox(width: 4),
        Text('Más', style: style),
      ],
    );
  }
}

/// Workouts and time per month for the last six months; a row opens the calendar there.
class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.workouts, required this.today, required this.onMonth});

  final List<Workout> workouts;
  final String today;
  final ValueChanged<String> onMonth;

  @override
  Widget build(BuildContext context) {
    final year = int.parse(today.substring(0, 4)), month = int.parse(today.substring(5, 7));
    final rows = <Widget>[];
    for (var i = 0; i < 6; i++) {
      final first = DateTime(year, month - i);
      final key = '${first.year.toString().padLeft(4, '0')}-${first.month.toString().padLeft(2, '0')}';
      final inMonth = workouts.where((w) => w.d.startsWith(key)).toList();
      rows.add(
        ListRow(
          title: WorkoutMonth(key, inMonth).label,
          value: inMonth.isEmpty
              ? '—'
              : '${inMonth.length} ${inMonth.length == 1 ? 'entreno' : 'entrenos'} · ${fmtDur(totalDuration(inMonth))}',
          accessory: RowAccessory.chevron,
          onTap: () => onMonth('$key-01'),
        ),
      );
    }
    return Section(title: 'Por mes', children: rows);
  }
}
