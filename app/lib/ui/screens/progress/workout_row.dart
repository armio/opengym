import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../widgets/widgets.dart';
import 'progress_data.dart';
import 'workout_detail_sheet.dart';

/// A finished workout in a list (specs/ui.md §4.17): the routine's glyph, the name,
/// "date · duration · sets · volume", a PR badge and how the session felt. Tapping opens
/// [onTap], by default the workout detail sheet.
class WorkoutRow extends StatelessWidget {
  const WorkoutRow({super.key, required this.workout, this.onTap});

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
    final rating = ratingLabels[w.rating];
    return ListItem(
      leading: IconBadge.routine(app.plan.routineById(w.routineId)?.emoji, size: BadgeSize.medium),
      title: w.name,
      subtitle: subtitle,
      trailing: [
        if (w.prs.isNotEmpty || rating != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (w.prs.isNotEmpty) PrBadge(text: '${w.prs.length} PR'),
              if (w.prs.isNotEmpty && rating != null) const SizedBox(height: 4),
              if (rating != null) Tag(rating, icon: ratingIcons[w.rating], capitalize: false),
            ],
          ),
        const Chevron(),
      ],
      onTap: onTap ?? () => showWorkoutDetailSheet(context, w),
    );
  }
}
