import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../../workout_launcher.dart';
import '../plan/plan_screen.dart';

/// "Empezar entrenamiento" (specs/ui.md §3.5), shown when no workout is active: today's routine
/// (with its reschedule), the other routines, a freestyle session, and — without any routine —
/// the way to the plan. Every start goes through the body-weight check-in.
class StartChooser extends StatelessWidget {
  const StartChooser({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final todayIso = app.clock.todayIso();
    final today = effectiveRoutine(app.plan, app.schedule, todayIso);
    final rescheduled = app.schedule.dayPlan.containsKey(todayIso);
    final others = [
      for (final r in app.plan.routines)
        if (r.id != today?.id) r,
    ];
    final launcher = context.read<WorkoutLauncher>();
    void start(String? id) => launcher.startRoutine(context, id);
    final navigator = Navigator.of(context);
    final day = dayNames[weekdayOf(todayIso)];
    return Scaffold(
      body: PageBody(
        children: [
          ScreenHeader(
            title: 'Empezar entrenamiento',
            subtitle: '$day — ${today != null ? 'hoy toca ${today.name}' : 'día de descanso, pero nadie te lo impide'}',
            leading: ModalRoute.of(context)?.isFirst == false
                ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: navigator.pop)
                : null,
          ),
          if (today != null) _TodayCard(routine: today, rescheduled: rescheduled, onStart: () => start(today.id)),
          if (others.isNotEmpty) ...[
            const SectionCaption('Otras rutinas'),
            ItemList(
              children: [
                for (final r in others)
                  ListItem(
                    title: r.name,
                    subtitle: exCount(r.ex.length),
                    leading: IconBadge.routine(r.emoji),
                    trailing: const [Tag('Empezar', accent: true)],
                    onTap: () => start(r.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          AppButton('Entrenamiento libre (elige sobre la marcha)', icon: 'shuffle', onPressed: () => start(null)),
          if (app.plan.routines.isEmpty) ...[
            const SizedBox(height: 10),
            AppButton(
              'Crea primero un plan',
              variant: ButtonVariant.primary,
              onPressed: () => navigator.push(MaterialPageRoute<void>(builder: (_) => const PlanScreen())),
            ),
          ],
        ],
      ),
    );
  }
}

/// The accent-outlined "Plan de hoy" card.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.routine, required this.rescheduled, required this.onStart});

  final Routine routine;
  final bool rescheduled;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    return AppCard(
      border: Border.all(color: p.acc, width: .5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Plan de hoy${rescheduled ? ' · reprogramado' : ''}', style: t.caption.copyWith(color: p.acc)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(routine.name, style: t.bigNumber),
                    const SizedBox(height: 2),
                    Text(exCount(routine.ex.length), style: t.small),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconBadge.routine(routine.emoji, size: BadgeSize.large),
            ],
          ),
          const SizedBox(height: 12),
          AppButton('Empezar ${routine.name}', icon: 'play', variant: ButtonVariant.primary, onPressed: onStart),
        ],
      ),
    );
  }
}
