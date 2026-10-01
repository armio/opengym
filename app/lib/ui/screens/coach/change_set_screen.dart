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

/// A `changes` proposal (specs/coach.md §7.2, §7.6): every change checked against the live
/// plan, applicable ones ticked, stale ones greyed out with the reason and no checkbox, the
/// plan-moved banner, Claude's notes, and "Aplicar N cambios" / "Descartar todo".
class ChangeSetScreen extends StatefulWidget {
  const ChangeSetScreen({super.key, required this.proposalId});

  final String proposalId;

  @override
  State<ChangeSetScreen> createState() => _ChangeSetScreenState();
}

class _ChangeSetScreenState extends State<ChangeSetScreen> {
  /// Ticked change ids; starts as every change applicable when the screen opened.
  Set<String>? _ticked;
  bool _busy = false;

  void _toggle(String id) => setState(() {
    final ticked = _ticked!;
    if (!ticked.remove(id)) ticked.add(id);
  });

  Future<void> _apply(ReviewedProposal reviewed) async {
    final ids = _tickedApplicable(reviewed);
    if (ids.isEmpty) return _dismiss(reviewed.proposal);
    setState(() => _busy = true);
    var applied = 0;
    final ok = await runCoachWrite(context, () async {
      applied = (await CoachFlows(context.read<AppState>()).applyChanges(reviewed.proposal, ids)).applied.length;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    if (applied == 0) {
      // Everything ticked went stale in the meantime: nothing was sent.
      showToast(context, 'Esos cambios ya no encajan con tu plan: no se ha aplicado nada.');
      return;
    }
    showToast(context, appliedToast(applied));
    leaveProposal(context, tab: AppTab.plan);
  }

  Future<void> _dismiss(Proposal proposal) async {
    final confirmed = await showConfirm(
      context,
      title: '¿Descartar estas sugerencias?',
      message: 'No cambia nada, y Claude sabrá que las has rechazado.',
      confirmText: 'Descartar',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final ok = await runCoachWrite(context, () => CoachFlows(context.read<AppState>()).dismissChanges(proposal));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    showToast(context, 'Sugerencias descartadas');
    leaveProposal(context);
  }

  Set<String> _tickedApplicable(ReviewedProposal reviewed) => {
    for (final c in reviewed.applicable)
      if (_ticked!.contains(c.id)) c.id,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final proposal = app.proposalById(widget.proposalId);
    if (proposal == null) return const MissingProposalScreen(title: 'Sugerencias');
    // Staleness is decided against the live plan on every build: a sync may have changed it.
    final reviewed = markStale(proposal, app.plan, app.exerciseIndex);
    _ticked ??= {for (final c in reviewed.applicable) c.id};
    final names = DisplayNameIndex(app.exerciseIndex);
    final count = _tickedApplicable(reviewed).length;
    final mismatch = unitMismatch(proposal, app.settings);
    return Scaffold(
      body: PageBody(
        children: [
          ScreenHeader(
            title: 'Sugerencias',
            subtitle: evidenceLine(proposal.evidence, recent: true),
            leading: const BackChevron(),
          ),
          const CoachOfflineNotice(),
          if (mismatch && proposal.isPending) UnitMismatchNotice(proposalUnit: proposal.unit),
          if (proposal.summary.isNotEmpty) ClaudeTextCard(proposal.summary),
          if (reviewed.planMoved && proposal.isPending)
            NoticeCard(icon: 'info', tint: context.palette.yellow, message: planMovedNote),
          for (final c in reviewed.changes)
            ChangeCard(
              change: c.change.raw,
              stale: c.stale && proposal.isPending,
              names: names,
              plan: app.plan,
              ticked: proposal.isPending && !c.stale ? _ticked!.contains(c.id) : null,
              onToggle: _busy ? null : () => _toggle(c.id),
            ),
          if (proposal.notes.isNotEmpty) _NotesCard(notes: proposal.notes),
          if (proposal.isPending) ...[
            AppButton(
              applyButtonLabel(count),
              variant: ButtonVariant.primary,
              icon: 'check',
              busy: _busy,
              onPressed: mismatch && count > 0 ? null : () => _apply(reviewed),
            ),
            const SizedBox(height: 8),
            AppButton(
              'Descartar todo',
              variant: ButtonVariant.danger,
              onPressed: _busy ? null : () => _dismiss(proposal),
            ),
          ] else
            ProposalClosedNotice(proposal: proposal),
        ],
      ),
    );
  }
}

/// One change of a change set: title, where it applies, before → after, Claude's reason and,
/// when [stale], why it can no longer be applied. [ticked] null hides the checkbox.
class ChangeCard extends StatelessWidget {
  const ChangeCard({
    super.key,
    required this.change,
    required this.names,
    required this.plan,
    this.stale = false,
    this.ticked,
    this.onToggle,
  });

  final JsonMap change;
  final ExerciseIndex names;
  final PlanDoc plan;
  final bool stale;
  final bool? ticked;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final title = capitalizeFirst(changeTitle(change, names));
    final values = changeValues(change, names, routineName: (id) => plan.routineById(id)?.name);
    final where = _where(change, plan);
    final why = asString(change['why']) ?? '';
    return Opacity(
      opacity: stale ? .55 : 1,
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.itemTitle.copyWith(fontWeight: FontWeight.w600, fontSize: 15)),
                  if (where != null) ...[const SizedBox(height: 2), Text(where, style: t.caption)],
                  if (values != null) ...[const SizedBox(height: 7), _BeforeAfter(values: values)],
                  if (why.isNotEmpty) ...[const SizedBox(height: 7), ClaudeText(why, dim: true)],
                  if (stale) ...[
                    const SizedBox(height: 6),
                    Text(staleChangeNote, style: t.small.copyWith(color: p.yellow)),
                  ],
                ],
              ),
            ),
            if (ticked != null) ...[
              const SizedBox(width: 10),
              RoundCheck(value: ticked!, onChanged: onToggle == null ? null : (_) => onToggle!(), semanticLabel: title),
            ],
          ],
        ),
      ),
    );
  }

  /// The routine the change is about ("En Full body A"), or the weekday of a `week` change.
  static String? _where(JsonMap change, PlanDoc plan) {
    final target = asMap(change['target']);
    if (change['type'] == 'week') {
      final day = asInt(target['weekday']);
      return day == null || day < 0 || day > 6 ? null : dayNames[day];
    }
    final routine = plan.routineById(asString(target['routineId']));
    return routine == null ? null : 'En ${routine.name}';
  }
}

class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.values});

  final ({String before, String after}) values;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Tag(values.before, capitalize: false),
      AppIcon('chevronRight', size: 14, color: context.palette.label3),
      Tag(values.after, accent: true, capitalize: false),
    ],
  );
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeading('Notas de Claude'),
          for (var i = 0; i < notes.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: Border(top: i == 0 ? BorderSide.none : BorderSide(color: p.sep, width: .5)),
              ),
              child: ClaudeText(notes[i]),
            ),
          const SizedBox(height: 4),
          Text('Por sí solas no cambian nada.', style: context.textStyles.caption),
        ],
      ),
    );
  }
}
