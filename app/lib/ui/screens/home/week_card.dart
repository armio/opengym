import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../plan/plan_screen.dart' show showDayOverrideSheet;

/// The week strip (specs/ui.md §3.2): Monday to Sunday of this week (‹ › browse other weeks;
/// the offset resets when Home is rebuilt from scratch), today in an accent circle, a dot per
/// day — trained (accent), rescheduled (orange), planned (grey). Tapping a day opens its
/// reschedule sheet.
class WeekCard extends StatefulWidget {
  const WeekCard({super.key});

  @override
  State<WeekCard> createState() => _WeekCardState();
}

class _WeekCardState extends State<WeekCard> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final today = app.clock.todayIso();
    final days = weekDates(addDays(today, 7 * _offset));
    final label = _offset == 0 ? 'Esta semana' : '${fmtDate(days.first)} – ${fmtDate(days.last)}';
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              AppIconButton(
                icon: 'chevronLeft',
                tooltip: 'Semana anterior',
                size: 30,
                iconSize: 15,
                onPressed: () => setState(() => _offset--),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.textStyles.caption.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              AppIconButton(
                icon: 'chevronRight',
                tooltip: 'Semana siguiente',
                size: 30,
                iconSize: 15,
                onPressed: () => setState(() => _offset++),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final iso in days)
                Expanded(
                  child: _DayCell(
                    iso: iso,
                    today: iso == today,
                    mark: dayMark(iso, workouts: app.workouts, plan: app.plan, schedule: app.schedule),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.iso, required this.today, required this.mark});

  final String iso;
  final bool today;
  final DayMark mark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final dot = switch (mark) {
      DayMark.done => p.acc,
      DayMark.rescheduled => p.orange,
      DayMark.planned => p.label3,
      DayMark.none => Colors.transparent,
    };
    final day = int.parse(iso.substring(8));
    return Pressable(
      onTap: () => showDayOverrideSheet(context, iso),
      pressedScale: 1,
      pressedColor: p.surface2,
      borderRadius: BorderRadius.circular(10),
      semanticLabel: fmtDate(iso, long: true),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 9),
        child: Column(
          children: [
            Text(dayLetters[weekdayOf(iso)].toUpperCase(), style: t.microCaps.copyWith(letterSpacing: 11 * .03)),
            const SizedBox(height: 2),
            Container(
              width: 31,
              height: 31,
              alignment: Alignment.center,
              decoration: today ? BoxDecoration(color: p.acc, shape: BoxShape.circle) : null,
              child: Text(
                '$day',
                style: t.rowTitle.copyWith(
                  color: today ? p.onAcc : p.label,
                  fontWeight: today ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
