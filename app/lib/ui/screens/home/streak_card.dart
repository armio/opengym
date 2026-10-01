import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../plan/plan_screen.dart' show showCalendarSheet;
import '../progress/workout_detail_sheet.dart' show showWorkoutDetailSheet;

/// The streak (specs/ui.md §3.2) — "racha de N semanas", this week against the plan and the
/// total — opening the calendar, then the month and 30-day weight tiles (`statsTiles`).
class StreakCard extends StatelessWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = app.clock.now();
    final tiles = statsTiles(app.workouts, app.bodyWeights, now: now);
    final thisWeek = workoutsThisWeek(app.workouts, now: now);
    final planned = plannedPerWeek(app.plan);
    final total = tiles.workouts;
    final p = context.palette;
    final t = context.textStyles;
    final change = tiles.weightChange30d;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          onTap: () => showCalendarSheet(context, openWorkout: showWorkoutDetailSheet),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppIcon('flame', size: 22, color: p.orange),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            tiles.streakWeeks == 1 ? 'racha de 1 semana' : 'racha de ${tiles.streakWeeks} semanas',
                            style: t.sheetTitle.copyWith(fontSize: 22),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$thisWeek${planned > 0 ? ' / $planned' : ''} esta semana · '
                      '${total == 1 ? '1 entrenamiento en total' : '$total entrenamientos en total'}',
                      style: t.small,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AppIcon('calendar', size: 20, color: p.label3),
            ],
          ),
        ),
        TileGrid(
          tiles: [
            StatTile(label: 'Este mes', icon: 'calendar', value: '${tiles.thisMonth}'),
            StatTile(
              label: 'Peso · 30 días',
              icon: 'scale',
              value: change == null ? '—' : _signedWeight(change, app.settings.unit),
            ),
          ],
        ),
      ],
    );
  }
}

/// `+1,2 kg`, `−0,8 kg`, `0 kg`.
String _signedWeight(num change, String unit) {
  final sign = change > 0 ? '+' : (change < 0 ? '−' : '');
  return '$sign${fmtVol(change.abs(), unit)}';
}
