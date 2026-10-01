import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'change_set_screen.dart';
import 'coach_flows.dart';
import 'coach_widgets.dart';
import 'plan_proposal_screen.dart';

/// Opens the review screen of a `plan` or `changes` proposal in the current tab.
void openProposal(BuildContext context, Proposal proposal) {
  final screen = proposal.kind == Proposal.kindPlan
      ? PlanProposalScreen(proposalId: proposal.id)
      : ChangeSetScreen(proposalId: proposal.id);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

/// Pending proposals, newest first: plans and change sets open their review screen; a reading
/// (`nochange`) is shown in place with "Entendido". With nothing pending, an empty state says
/// where Claude's proposals will arrive.
class PendingProposalsSection extends StatelessWidget {
  const PendingProposalsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<AppState>().pendingProposals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(pending.isEmpty ? 'Propuestas' : 'Propuestas pendientes (${pending.length})'),
        if (pending.isEmpty)
          const _NothingPending()
        else
          for (final p in pending)
            p.kind == Proposal.kindNoChange
                ? ReadingCard(proposal: p)
                : ProposalCard(proposal: p, onTap: () => openProposal(context, p)),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _NothingPending extends StatelessWidget {
  const _NothingPending();

  @override
  Widget build(BuildContext context) => const AppCard(
    child: EmptyState(
      icon: 'sparkles',
      message:
          'No hay propuestas pendientes.\n'
          'Cuando pidas a Claude un plan o una revisión, sus propuestas llegarán aquí para que '
          'decidas qué aplicar.',
    ),
  );
}

/// The kind badge of a proposal.
class ProposalKindTag extends StatelessWidget {
  const ProposalKindTag({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return switch (kind) {
      Proposal.kindPlan => const Tag('Plan nuevo', accent: true, capitalize: false),
      Proposal.kindChanges => Tag('Cambios', color: p.blue, background: p.blue.withValues(alpha: .16)),
      _ => Tag('Sin cambios', color: p.indigo, background: p.indigo.withValues(alpha: .18)),
    };
  }
}

/// A pending plan or change set: what it is, how much there is to review, Claude's summary.
class ProposalCard extends StatelessWidget {
  const ProposalCard({super.key, required this.proposal, required this.onTap});

  final Proposal proposal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final plan = proposal.kind == Proposal.kindPlan;
    final summary = plan ? (proposal.bundle?.summary ?? proposal.summary) : proposal.summary;
    return AppCard(
      onTap: onTap,
      border: Border.all(color: p.accLine),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: plan ? 'calendar' : 'clipboard'),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan ? 'Tu plan está listo' : 'Sugerencias listas', style: t.caption),
                    const SizedBox(height: 1),
                    Text(_headline(proposal), style: t.itemTitle.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Tag('Revisar', accent: true, capitalize: false),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.small.copyWith(height: 1.45)),
          ],
          const SizedBox(height: 10),
          _Footer(proposal: proposal),
        ],
      ),
    );
  }

  static String _headline(Proposal p) {
    if (p.kind == Proposal.kindPlan) {
      final n = p.bundle?.routines.length ?? 0;
      return n == 1 ? '1 rutina para revisar' : '$n rutinas para revisar';
    }
    final n = p.changes.length;
    return n == 1 ? '1 sugerencia' : '$n sugerencias';
  }
}

/// Kind badge, date received and revision number.
class _Footer extends StatelessWidget {
  const _Footer({required this.proposal});

  final Proposal proposal;

  @override
  Widget build(BuildContext context) {
    final parts = [
      'Recibida el ${dateOfMs(proposal.createdAt)}',
      if (proposal.iteration > 1) 'revisión ${proposal.iteration}',
    ];
    return Row(
      children: [
        ProposalKindTag(kind: proposal.kind),
        const SizedBox(width: 8),
        Expanded(
          child: Text(parts.join(' · '), style: context.textStyles.caption, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// A `nochange` proposal: Claude's reading of the training, acknowledged with "Entendido".
class ReadingCard extends StatefulWidget {
  const ReadingCard({super.key, required this.proposal});

  final Proposal proposal;

  @override
  State<ReadingCard> createState() => _ReadingCardState();
}

class _ReadingCardState extends State<ReadingCard> {
  bool _busy = false;

  Future<void> _acknowledge() async {
    setState(() => _busy = true);
    final ok = await runCoachWrite(context, () => CoachFlows(context.read<AppState>()).acknowledge(widget.proposal));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) showToast(context, 'Lectura archivada');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final reading = widget.proposal.reading.isNotEmpty ? widget.proposal.reading : widget.proposal.summary;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: 'lightbulb', tint: p.indigo),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lectura de Claude', style: t.caption),
                    const SizedBox(height: 1),
                    Text('Tu plan puede seguir igual', style: t.itemTitle.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (reading.isNotEmpty) ...[const SizedBox(height: 10), ClaudeText(reading)],
          const SizedBox(height: 10),
          _Footer(proposal: widget.proposal),
          const SizedBox(height: 12),
          AppButton('Entendido', variant: ButtonVariant.tinted, busy: _busy, onPressed: _acknowledge),
        ],
      ),
    );
  }
}
