import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../shell.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'coach_flows.dart';
import 'coach_widgets.dart';

/// A `plan` proposal (specs/coach.md §7.7, contract §6): Claude's summary and reasoning, every
/// routine with its exercises and why, the "Usar este horario semanal" switch, and
/// "Aceptar plan" / "Descartar". There is no refine box: changes are asked of Claude.
class PlanProposalScreen extends StatefulWidget {
  const PlanProposalScreen({super.key, required this.proposalId});

  final String proposalId;

  @override
  State<PlanProposalScreen> createState() => _PlanProposalScreenState();
}

class _PlanProposalScreenState extends State<PlanProposalScreen> {
  bool _schedule = true;
  bool _busy = false;

  Future<void> _run(Future<void> Function(CoachFlows flows) write, {required String done, AppTab? then}) async {
    setState(() => _busy = true);
    final ok = await runCoachWrite(context, () => write(CoachFlows(context.read<AppState>())));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    showToast(context, done);
    leaveProposal(context, tab: then);
  }

  Future<void> _accept(Proposal p) => _run(
    (f) => f.acceptPlan(p, schedule: _schedule),
    done: 'Tu plan ya está activo',
    then: AppTab.plan,
  );

  Future<void> _discard(Proposal p) async {
    final confirmed = await showConfirm(
      context,
      title: '¿Descartar este plan?',
      message: 'No se guarda nada y puedes volver a pedírselo a Claude cuando quieras.',
      confirmText: 'Descartar',
      danger: true,
    );
    if (confirmed && mounted) await _run((f) => f.dismissPlan(p), done: 'Plan descartado');
  }

  /// The plan's name and, from the second iteration on, "Revisión N".
  static String? _subtitle(PlanBundle bundle, Proposal proposal) {
    final parts = [
      if (bundle.name.isNotEmpty) bundle.name,
      if (proposal.iteration > 1) 'Revisión ${proposal.iteration}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final proposal = app.proposalById(widget.proposalId);
    final bundle = proposal?.bundle;
    if (proposal == null || bundle == null) {
      return const MissingProposalScreen(title: 'Tu plan');
    }
    final names = DisplayNameIndex(
      app.exerciseIndex.withCustoms([for (final c in bundle.customEx) CustomExercise.fromJson(c)]),
    );
    final mismatch = unitMismatch(proposal, app.settings);
    return Scaffold(
      body: PageBody(
        children: [
          ScreenHeader(title: 'Tu plan', subtitle: _subtitle(bundle, proposal), leading: const BackChevron()),
          const CoachOfflineNotice(),
          if (mismatch && proposal.isPending) UnitMismatchNotice(proposalUnit: proposal.unit),
          if (bundle.summary.isNotEmpty || bundle.basedOn.isNotEmpty)
            ClaudeTextCard(bundle.summary, secondary: bundle.basedOn),
          for (final r in bundle.routines) _BundleRoutineCard(routine: r, names: names, unit: proposal.unit),
          if (proposal.isPending) ...[
            _ScheduleCard(
              bundle: bundle,
              value: _schedule,
              onChanged: _busy ? null : (v) => setState(() => _schedule = v),
            ),
            const _RefineHint(),
            AppButton(
              'Aceptar plan',
              variant: ButtonVariant.primary,
              icon: 'check',
              busy: _busy,
              onPressed: mismatch ? null : () => _accept(proposal),
            ),
            const SizedBox(height: 8),
            AppButton('Descartar', variant: ButtonVariant.danger, onPressed: _busy ? null : () => _discard(proposal)),
          ] else
            ProposalClosedNotice(proposal: proposal),
        ],
      ),
    );
  }
}

/// One routine of the bundle: icon, name, exercise count, why, and each exercise with its
/// scheme line and why. Supersets carry the accent bar.
class _BundleRoutineCard extends StatelessWidget {
  const _BundleRoutineCard({required this.routine, required this.names, required this.unit});

  final Routine routine;
  final ExerciseIndex names;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    final why = PlanBundle.routineWhy(routine);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge.routine(routine.emoji),
              const SizedBox(width: 10),
              Expanded(
                child: Text(routine.name, style: t.itemTitle.copyWith(fontWeight: FontWeight.w600, fontSize: 18)),
              ),
              const SizedBox(width: 8),
              Text(exCount(routine.ex.length), style: t.caption),
            ],
          ),
          if (why.isNotEmpty) ...[const SizedBox(height: 8), ClaudeText(why, dim: true)],
          const SizedBox(height: 6),
          for (var i = 0; i < routine.ex.length; i++)
            _BundleExerciseRow(exercise: routine.ex[i], names: names, unit: unit, first: i == 0),
        ],
      ),
    );
  }
}

class _BundleExerciseRow extends StatelessWidget {
  const _BundleExerciseRow({required this.exercise, required this.names, required this.unit, required this.first});

  final RoutineExercise exercise;
  final ExerciseIndex names;
  final String unit;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final why = PlanBundle.exerciseWhy(exercise);
    final superset = exercise.sg != null && exercise.sg!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: first ? BorderSide.none : BorderSide(color: p.sep, width: .5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Container(
        padding: EdgeInsets.only(left: superset ? 9 : 0),
        decoration: BoxDecoration(
          border: superset ? Border(left: BorderSide(color: p.acc, width: 3)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    names.nameOf(exercise.id),
                    style: t.small.copyWith(color: p.label, fontWeight: FontWeight.w500, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 10),
                Text(exLine(names, exercise, unit), style: t.small),
              ],
            ),
            if (why.isNotEmpty) ...[
              const SizedBox(height: 3),
              ClaudeText(why, dim: true, style: t.small.copyWith(fontSize: 12.5, color: p.label3, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Usar este horario semanal" with what it replaces, and the week the plan proposes.
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.bundle, required this.value, required this.onChanged});

  final PlanBundle bundle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    final routines = {for (final r in bundle.routines) r.id: r.name};
    final days = [
      for (final d in const [1, 2, 3, 4, 5, 6, 0])
        if (routines[bundle.week['$d']] case final name?) '${dayLetters[d]} · $name',
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Usar este horario semanal', style: t.rowTitle)),
              const SizedBox(width: 12),
              AppSwitch(value: value, onChanged: onChanged, semanticLabel: 'Usar este horario semanal'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sustituye tu semana actual. Los días que este plan deje vacíos serán de descanso.',
            style: t.caption.copyWith(height: 1.4),
          ),
          if (days.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final d in days) Tag(d, accent: value, capitalize: false)]),
          ],
        ],
      ),
    );
  }
}

class _RefineHint extends StatelessWidget {
  const _RefineHint();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
    child: Text(
      '¿Quieres algo distinto? Para pedir cambios, díselo a Claude: te propondrá una versión revisada.',
      style: context.textStyles.caption.copyWith(height: 1.4),
    ),
  );
}
