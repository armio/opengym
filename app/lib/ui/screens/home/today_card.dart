import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../shell.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import '../../workout_launcher.dart';
import '../plan/plan_screen.dart' show loadStarterPlanWithToast, showDayOverrideSheet;
import '../workout/workout_screen.dart' show ElapsedText;

/// What to do today (specs/ui.md §3.2): the workout in progress, today's routine, a rest day,
/// or — without any routine — the welcome card.
class TodaySection extends StatelessWidget {
  const TodaySection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.active;
    if (active != null) return ActiveWorkoutBanner(active: active);
    if (app.plan.routines.isEmpty) return const WelcomeCard();
    final today = app.clock.todayIso();
    final routine = effectiveRoutine(app.plan, app.schedule, today);
    if (routine == null) return RestDayCard(iso: today);
    return TodayRoutineCard(routine: routine, rescheduled: app.schedule.dayPlan.containsKey(today));
  }
}

/// "TODAY" caption + title, with a leading badge (the `.today-row` look).
class _TodayHeading extends StatelessWidget {
  const _TodayHeading({required this.badge, required this.caption, required this.title, this.trailing});

  final Widget badge;
  final String caption;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    return Row(
      children: [
        badge,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(caption.toUpperCase(), style: t.microCaps),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.rowTitle.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

/// The workout in progress: its clock and sets, and "Seguir".
class ActiveWorkoutBanner extends StatelessWidget {
  const ActiveWorkoutBanner({super.key, required this.active});

  final ActiveWorkout active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final done = setsDoneActive(active), total = setsTotalActive(active);
    return AppCard(
      border: Border.all(color: p.orange, width: .5),
      onTap: () => context.read<WorkoutLauncher>().openWorkout(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TodayHeading(
            badge: IconBadge(icon: 'timer', tint: p.orange, foreground: Colors.black),
            caption: 'Entrenamiento en curso',
            title: '${active.name} — en curso',
            trailing: Tag('Seguir', color: p.orange, background: p.orangeSoft),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElapsedText(
                start: active.start,
                style: t.small.copyWith(color: p.label2),
              ),
              Text(' · $done/$total series', style: t.small),
            ],
          ),
        ],
      ),
    );
  }
}

/// Today's routine: the reschedule note, the exercises it holds and "Empezar".
class TodayRoutineCard extends StatelessWidget {
  const TodayRoutineCard({super.key, required this.routine, required this.rescheduled});

  final Routine routine;
  final bool rescheduled;

  static const _preview = 4;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final t = context.textStyles;
    final p = context.palette;
    final shown = routine.ex.take(_preview).toList();
    final more = routine.ex.length - shown.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TodayHeading(
            badge: IconBadge.routine(routine.emoji),
            caption: rescheduled ? 'Hoy · reprogramado' : 'Hoy',
            title: routine.name,
            trailing: Text(exCount(routine.ex.length), style: t.small),
          ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final cfg in shown)
              _ExercisePreviewRow(
                name: capitalizeWords(app.catalog.exOr(cfg.id).name),
                line: exLine(app.exerciseIndex, cfg, app.settings.unit),
              ),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  more == 1 ? '+1 ejercicio más' : '+$more ejercicios más',
                  style: t.small.copyWith(color: p.label3),
                ),
              ),
          ],
          const SizedBox(height: 14),
          AppButton(
            'Empezar ${routine.name}',
            icon: 'play',
            variant: ButtonVariant.primary,
            onPressed: () => context.read<WorkoutLauncher>().startRoutine(context, routine.id),
          ),
        ],
      ),
    );
  }
}

class _ExercisePreviewRow extends StatelessWidget {
  const _ExercisePreviewRow({required this.name, required this.line});

  final String name;
  final String line;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body.copyWith(fontSize: 15)),
          ),
          const SizedBox(width: 10),
          Text(line, style: t.small),
        ],
      ),
    );
  }
}

/// Nothing planned today: plan something for the day, or train anyway.
class RestDayCard extends StatelessWidget {
  const RestDayCard({super.key, required this.iso});

  final String iso;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      onTap: () => showDayOverrideSheet(context, iso),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TodayHeading(
            badge: IconBadge(icon: 'moon', tint: p.surface3),
            caption: 'Hoy',
            title: 'Día de descanso',
            trailing: AppIcon('plus', size: 18, color: p.label3),
          ),
          const SizedBox(height: 10),
          Text('Recupera, o toca para planificar una sesión hoy.', style: context.textStyles.small),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              'Entrenar igualmente',
              icon: 'dumbbell',
              size: ButtonSize.sm,
              onPressed: () => context.read<WorkoutLauncher>().openWorkout(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// No routines yet: ask Claude for a plan, load the starter plan, or build one.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    final shell = context.read<ShellController?>();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: 'sparkles'),
              const SizedBox(width: 10),
              Text('¡Bienvenido!', style: t.bigNumber.copyWith(fontSize: 22)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Configura tu rutina semanal para empezar: pídele un plan a Claude, carga un plan '
            'Empuje / Tirón / Pierna ya hecho o crea el tuyo.',
            style: t.small,
          ),
          const SizedBox(height: 12),
          AppButton(
            'Pídele un plan a Claude',
            icon: 'sparkles',
            variant: ButtonVariant.primary,
            onPressed: shell == null ? null : () => shell.goTo(AppTab.coach),
          ),
          const SizedBox(height: 8),
          AppButton('Cargar plan inicial', icon: 'clipboard', onPressed: () => loadStarterPlanWithToast(context)),
          AppButton(
            'Crear mi propio plan',
            icon: 'pencil',
            onPressed: shell == null ? null : () => shell.goTo(AppTab.plan),
          ),
        ],
      ),
    );
  }
}
