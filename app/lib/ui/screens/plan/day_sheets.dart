import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'routine_editing.dart';

/// The weekday sheet of the Plan tab (specs/ui.md §6.1): "Día de descanso" or any routine for
/// [weekday] (0 = Sunday … 6 = Saturday); the current choice is checked. Picking closes the sheet
/// and writes `plan.week`.
Future<void> showDayAssignSheet(BuildContext context, int weekday) async {
  final choice = await showAppSheet<_Choice>(
    context,
    title: dayNames[weekday],
    builder: (ctx) {
      final plan = ctx.watch<AppState>().plan;
      final assigned = plan.week['$weekday'];
      void pick(_Choice c) => Navigator.of(ctx).pop(c);
      return ItemList(
        children: [
          _ChoiceItem.rest(
            title: 'Día de descanso',
            checked: assigned == null || assigned.isEmpty,
            onTap: () => pick(const _Choice(null)),
          ),
          for (final r in plan.routines)
            _ChoiceItem.routine(r, checked: assigned == r.id, onTap: () => pick(_Choice(r.id))),
        ],
      );
    },
  );
  if (choice == null || !context.mounted) return;
  context.read<AppState>().updatePlan((plan) => assignWeekday(plan, weekday, choice.value));
}

/// The reschedule sheet for one date (specs/ui.md §6.2), from the Home week strip, the Home
/// "today" row on a rest day and the calendar: train any routine or rest on [iso] instead of
/// what the week plans, or go back to the weekly plan. Writes `schedule.dayPlan` and toasts.
/// Past dates are allowed; picking the week's own routine still stores an override.
Future<void> showDayOverrideSheet(BuildContext context, String iso) async {
  final choice = await showAppSheet<_Choice>(
    context,
    title: fmtDate(iso, long: true),
    builder: (_) => _DayOverride(iso: iso),
  );
  if (choice == null || !context.mounted) return;
  final app = context.read<AppState>();
  final value = choice.value;
  final routineName = app.plan.routineById(value)?.name;
  app.updateSchedule((s) => rescheduleDate(s, iso, value));
  showToast(context, switch (value) {
    null || '' => 'Volver al plan semanal',
    'rest' => '${fmtDate(iso)} marcado como descanso',
    _ => '${routineName ?? ''} planificado para ${fmtDate(iso)}',
  });
}

/// A picked option: a routine id, `'rest'`, or null (rest day / back to the weekly plan).
class _Choice {
  const _Choice(this.value);

  final String? value;
}

class _DayOverride extends StatelessWidget {
  const _DayOverride({required this.iso});

  final String iso;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final plan = app.plan;
    final weekly = plan.routineById(plan.week['${weekdayOf(iso)}']);
    final hasOverride = app.schedule.dayPlan.containsKey(iso);
    final effective = effectiveRoutineId(plan, app.schedule, iso);
    void pick(_Choice c) => Navigator.of(context).pop(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _WeeklyPlanNote(weekly: weekly, hasOverride: hasOverride),
        const SizedBox(height: 12),
        ItemList(
          children: [
            for (final r in plan.routines)
              _ChoiceItem.routine(r, checked: effective == r.id, onTap: () => pick(_Choice(r.id))),
            _ChoiceItem.rest(
              title: 'Descansar / saltar este día',
              checked: effective == null,
              onTap: () => pick(const _Choice('rest')),
            ),
            if (hasOverride)
              _ChoiceItem.neutral(
                icon: 'reset',
                title: 'Volver al plan semanal',
                onTap: () => pick(const _Choice(null)),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Plan semanal: Empuje · cambiado para este día" and the explanation below it.
class _WeeklyPlanNote extends StatelessWidget {
  const _WeeklyPlanNote({required this.weekly, required this.hasOverride});

  final Routine? weekly;
  final bool hasOverride;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = context.textStyles.small;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: 'Plan semanal: ${weekly?.name ?? 'Descanso'}'),
          if (hasOverride)
            TextSpan(
              text: ' · cambiado para este día',
              style: TextStyle(color: p.orange),
            ),
          const TextSpan(text: '\n¿Enfermo, te saltaste un día o quieres otra sesión? Elige qué entrenar en su lugar.'),
        ],
      ),
    );
  }
}

/// One option of the day sheets: a routine (glyph badge, name, exercise count) or a neutral
/// choice (rest, back to the week) on a grey badge; a check marks the current one.
class _ChoiceItem extends StatelessWidget {
  const _ChoiceItem._({
    required this.title,
    required this.badge,
    this.subtitle,
    this.checked = false,
    required this.onTap,
  });

  factory _ChoiceItem.routine(Routine r, {required bool checked, required VoidCallback onTap}) => _ChoiceItem._(
    title: r.name,
    subtitle: exCount(r.ex.length),
    badge: IconBadge.routine(r.emoji),
    checked: checked,
    onTap: onTap,
  );

  factory _ChoiceItem.rest({required String title, required bool checked, required VoidCallback onTap}) =>
      _ChoiceItem.neutral(icon: 'moon', title: title, checked: checked, onTap: onTap);

  factory _ChoiceItem.neutral({
    required String icon,
    required String title,
    bool checked = false,
    required VoidCallback onTap,
  }) => _ChoiceItem._(title: title, badge: _NeutralBadge(icon), checked: checked, onTap: onTap);

  final String title;
  final String? subtitle;
  final Widget badge;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: checked,
    child: ListItem(
      leading: badge,
      title: title,
      subtitle: subtitle,
      trailing: [if (checked) AppIcon('check', size: 18, color: context.palette.acc)],
      onTap: onTap,
    ),
  );
}

class _NeutralBadge extends StatelessWidget {
  const _NeutralBadge(this.icon);

  final String icon;

  @override
  Widget build(BuildContext context) =>
      IconBadge(icon: icon, tint: context.palette.surface3, foreground: context.palette.label);
}
