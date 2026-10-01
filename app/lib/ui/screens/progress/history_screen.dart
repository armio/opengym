import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'progress_data.dart';
import 'workout_row.dart';

/// Every workout, newest first, grouped by month (specs/ui.md §3.7). A row opens the workout
/// detail sheet.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  /// Pushes the history onto the current tab's stack.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen()));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final months = workoutsByMonth(app.workouts);
    final navigator = Navigator.of(context);
    return Scaffold(
      body: PageBody(
        onRefresh: app.sync,
        children: [
          ScreenHeader(
            title: 'Historial',
            subtitle: workoutCount(app.workouts.length),
            leading: navigator.canPop()
                ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: navigator.pop)
                : null,
          ),
          if (months.isEmpty) const EmptyState(icon: 'history', message: 'Aún no hay entrenamientos.'),
          for (final month in months) _MonthGroup(month: month),
        ],
      ),
    );
  }
}

class _MonthGroup extends StatelessWidget {
  const _MonthGroup({required this.month});

  final WorkoutMonth month;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(
          month.label,
          trailing: Text(workoutCount(month.workouts.length), style: context.textStyles.caption),
        ),
        ItemList(
          children: [for (final w in month.workouts) WorkoutRow(key: ValueKey(w.id), workout: w)],
        ),
      ],
    ),
  );
}
