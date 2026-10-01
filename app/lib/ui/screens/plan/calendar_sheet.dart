import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/dates.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'day_sheets.dart';

/// Opens a finished workout's detail sheet (specs/ui.md §4.15). The screen that owns that sheet
/// passes it in; the calendar only decides when to call it.
typedef WorkoutDetailOpener = Future<void> Function(BuildContext context, Workout workout);

/// The month calendar (specs/ui.md §6.3), opened at the month of [startIso] (read as a local
/// date — critic-G2) or of today. Days show trained / rescheduled / planned dots; the summary
/// counts the month's workouts, time and volume.
///
/// Tapping a day closes the calendar and then: no workouts → the reschedule sheet for that date;
/// one workout → [openWorkout]; several → a list of that day's workouts, each opening
/// [openWorkout]. Without [openWorkout], days with workouts only show that list.
Future<void> showCalendarSheet(BuildContext context, {String? startIso, WorkoutDetailOpener? openWorkout}) async {
  final app = context.read<AppState>();
  final start = parseIsoDate(startIso) ?? app.clock.now();
  final iso = await showAppSheet<String>(
    context,
    builder: (_) => _Calendar(initialMonth: DateTime(start.year, start.month)),
  );
  if (iso == null || !context.mounted) return;
  final workouts = app.workouts.where((w) => w.d == iso).toList();
  if (workouts.isEmpty) return showDayOverrideSheet(context, iso);
  if (workouts.length == 1 && openWorkout != null) return openWorkout(context, workouts.single);
  final picked = await showAppSheet<Workout>(
    context,
    title: fmtDate(iso, long: true),
    builder: (ctx) => ItemList(
      children: [
        for (final w in workouts)
          _WorkoutRow(workout: w, onTap: openWorkout == null ? null : () => Navigator.of(ctx).pop(w)),
      ],
    ),
  );
  if (picked != null && openWorkout != null && context.mounted) await openWorkout(context, picked);
}

class _Calendar extends StatefulWidget {
  const _Calendar({required this.initialMonth});

  /// The 1st of the month shown first.
  final DateTime initialMonth;

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  late DateTime _month = widget.initialMonth;

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = context.textStyles;
    final prefix = '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}-';
    final monthWorkouts = app.workouts.where((w) => w.d.startsWith(prefix)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AppIconButton(icon: 'chevronLeft', tooltip: 'Mes anterior', onPressed: () => _shift(-1)),
            Expanded(
              child: Text(
                '${monthNames[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: t.sheetTitle,
              ),
            ),
            AppIconButton(icon: 'chevronRight', tooltip: 'Mes siguiente', onPressed: () => _shift(1)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _summary(monthWorkouts, app.settings.unit),
          textAlign: TextAlign.center,
          style: t.small.copyWith(color: context.palette.label2),
        ),
        const SizedBox(height: 10),
        _MonthGrid(
          month: _month,
          today: app.clock.todayIso(),
          workouts: monthWorkouts,
          plan: app.plan,
          schedule: app.schedule,
          onDay: (iso) => Navigator.of(context).pop(iso),
        ),
        const _Legend(),
        const SizedBox(height: 10),
        Text(
          'Toca un día entrenado para ver detalles · toca cualquier otro día para planificar',
          textAlign: TextAlign.center,
          style: t.small.copyWith(color: context.palette.label3),
        ),
      ],
    );
  }

  static String _summary(List<Workout> workouts, String unit) {
    if (workouts.isEmpty) return 'Sin entrenamientos este mes';
    final ms = workouts.fold<int>(0, (a, w) => a + math.max(0, (w.end != 0 ? w.end : w.start) - w.start));
    final vol = workouts.fold<num>(0, (a, w) => a + w.vol);
    final count = workouts.length == 1 ? '1 entrenamiento' : '${workouts.length} entrenamientos';
    return '$count · ${fmtDur(ms)} · ${fmtVol(vol, unit)}';
  }
}

/// Monday-first 7-column grid of one month.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.workouts,
    required this.plan,
    required this.schedule,
    required this.onDay,
  });

  final DateTime month;
  final String today;

  /// The month's workouts (the trained days).
  final List<Workout> workouts;
  final PlanDoc plan;
  final ScheduleDoc schedule;
  final ValueChanged<String> onDay;

  static const double _gap = 5;
  static const _headers = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];

  @override
  Widget build(BuildContext context) {
    final leading = month.weekday - 1; // Monday = 0
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++) _dayCell(isoDate(DateTime(month.year, month.month, d)), d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    return Column(
      children: [
        _row([
          for (final h in _headers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(h.toUpperCase(), textAlign: TextAlign.center, style: context.textStyles.microCaps),
            ),
        ]),
        for (var i = 0; i < cells.length; i += 7) ...[const SizedBox(height: _gap), _row(cells.sublist(i, i + 7))],
      ],
    );
  }

  Widget _row(List<Widget> children) => Row(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: _gap),
        Expanded(child: children[i]),
      ],
    ],
  );

  Widget _dayCell(String iso, int day) => _DayCell(
    day: day,
    mark: dayMark(iso, workouts: workouts, plan: plan, schedule: schedule),
    today: iso == today,
    onTap: () => onDay(iso),
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.mark, required this.today, required this.onTap});

  final int day;
  final DayMark mark;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final trained = mark == DayMark.done;
    final dot = switch (mark) {
      DayMark.done => p.acc,
      DayMark.rescheduled => p.orange,
      DayMark.planned => p.label3,
      DayMark.none => Colors.transparent,
    };
    return Semantics(
      button: true,
      label: '$day',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        pressedScale: 1,
        color: trained ? p.accSoft : p.surface,
        pressedColor: p.surface2,
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: today ? Border.all(color: p.acc, width: 1.8) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$day', style: TextStyle(fontSize: 15, color: trained ? p.acc : p.label)),
                const SizedBox(height: 3),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: p.label3)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 4,
        children: [item(p.acc, 'Entrenado'), item(p.label3, 'Planificado'), item(p.orange, 'Reprogramado')],
      ),
    );
  }
}

/// A finished workout in a list (specs/ui.md §4.17): routine glyph, name, date · duration ·
/// sets · volume, PR count.
class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({required this.workout, this.onTap});

  final Workout workout;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final w = workout;
    final subtitle = [
      fmtDate(w.d, long: true),
      ...durPart(w.end - w.start),
      '${setsDone(w)} series',
      fmtVol(w.vol, app.settings.unit),
    ].join(' · ');
    return ListItem(
      leading: IconBadge.routine(app.plan.routineById(w.routineId)?.emoji, size: BadgeSize.medium),
      title: w.name,
      subtitle: subtitle,
      trailing: [
        if (w.prs.isNotEmpty) PrBadge(text: '${w.prs.length} PR'),
        if (onTap != null) const Chevron(),
      ],
      onTap: onTap,
    );
  }
}
