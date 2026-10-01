import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/dates.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';

/// Text written by Claude (summaries, reasons, notes, readings): plain and selectable — never
/// Markdown, never auto-linked (contract §6 "Look").
class ClaudeText extends StatelessWidget {
  const ClaudeText(this.text, {super.key, this.style, this.dim = false});

  final String text;
  final TextStyle? style;

  /// label-3 instead of label-2 (the original's `dim` for per-item reasons).
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SelectableText(
      text,
      style: style ?? context.textStyles.small.copyWith(height: 1.5, color: dim ? p.label3 : p.label2),
    );
  }
}

/// A card holding a block of Claude's text (a summary), full width, with an optional dim line
/// under it (the plan's `basedOn`).
class ClaudeTextCard extends StatelessWidget {
  const ClaudeTextCard(this.text, {super.key, this.secondary = ''});

  final String text;
  final String secondary;

  @override
  Widget build(BuildContext context) => AppCard(
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty) ClaudeText(text),
          if (secondary.isNotEmpty) ...[
            if (text.isNotEmpty) const SizedBox(height: 8),
            ClaudeText(secondary, dim: true),
          ],
        ],
      ),
    ),
  );
}

/// A card with a tinted icon and a message: the plan-moved banner, the offline notice, the
/// "Claude actualizó tu perfil" banner. [tint] also colours the outline.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.icon,
    required this.tint,
    required this.message,
    this.title,
    this.actions = const [],
    this.onClose,
  });

  /// [AppIcons] name.
  final String icon;
  final Color tint;
  final String? title;
  final String message;

  /// Small buttons under the message.
  final List<Widget> actions;

  /// Shows a close button that calls this.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    return AppCard(
      border: Border.all(color: tint.withValues(alpha: .6)),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, tint: tint),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: t.itemTitle.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                ],
                Text(message, style: t.small.copyWith(color: p.label, height: 1.45)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
          if (onClose != null)
            AppIconButton(
              icon: 'xmark',
              tooltip: 'Cerrar',
              size: 28,
              iconSize: 15,
              background: Colors.transparent,
              color: p.label3,
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

/// Shown while the device cannot reach the server: accepting, dismissing and undoing are online
/// only and nothing is queued for later (contract §4.3).
class CoachOfflineNotice extends StatelessWidget {
  const CoachOfflineNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final offline = context.select<AppState, bool>((s) => s.syncStatus == SyncStatus.offline);
    if (!offline) return const SizedBox.shrink();
    return NoticeCard(
      icon: 'globe',
      tint: context.palette.orange,
      title: 'Sin conexión',
      message:
          'Aceptar, descartar o deshacer propuestas necesita conexión con tu servidor. '
          'No se guarda nada para más tarde.',
    );
  }
}

/// The back chevron of a pushed Coach screen.
class BackChevron extends StatelessWidget {
  const BackChevron({super.key, this.onPressed});

  /// Defaults to popping the route.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: 'chevronLeft',
    tooltip: 'Atrás',
    onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
  );
}

/// A grey subheading inside a card (`h2` of the original cards).
class CardHeading extends StatelessWidget {
  const CardHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(text, style: context.textStyles.itemTitle.copyWith(fontWeight: FontWeight.w600)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// An [ExerciseIndex] whose names are Title Case for display (the dataset's are lowercase), so
/// the engine's Spanish change titles read "Cambiar Barbell Curl por Hammer Curl".
class DisplayNameIndex extends ExerciseIndex {
  const DisplayNameIndex(this.base);

  final ExerciseIndex base;

  @override
  ExerciseFacts? lookup(String id) => base.lookup(id);

  @override
  String nameOf(String? id) {
    final facts = id == null ? null : base.lookup(id);
    return facts == null ? unknownExerciseName : capitalizeWords(facts.name);
  }
}

/// `"30 sept"` of an epoch-ms instant, in local time.
String dateOfMs(int ms, {bool long = false}) => fmtDate(isoDate(DateTime.fromMillisecondsSinceEpoch(ms)), long: long);

/// A proposal's state once it is no longer pending, as a phrase ("ya se aplicó").
String proposalStatusText(String status) => switch (status) {
  'applied' => 'ya se aplicó',
  'dismissed' => 'ya se descartó',
  'superseded' => 'Claude la sustituyó por una más nueva',
  'expired' => 'caducó sin respuesta',
  _ => 'ya no está pendiente',
};

/// Shown in place of the buttons of a proposal that stopped being pending while it was open
/// (resolved on another device, superseded, expired — e.g. after a 409).
class ProposalClosedNotice extends StatelessWidget {
  const ProposalClosedNotice({super.key, required this.proposal});

  final Proposal proposal;

  @override
  Widget build(BuildContext context) => NoticeCard(
    icon: 'info',
    tint: context.palette.grey,
    title: 'Esta propuesta ya no está pendiente',
    message: 'La propuesta ${proposalStatusText(proposal.status)}. No hay nada que decidir aquí.',
  );
}

/// The unit guard (contract §4.2): a proposal written for another unit cannot be accepted.
class UnitMismatchNotice extends StatelessWidget {
  const UnitMismatchNotice({super.key, required this.proposalUnit});

  final String proposalUnit;

  @override
  Widget build(BuildContext context) => NoticeCard(
    icon: 'scale',
    tint: context.palette.red,
    title: 'Unidad distinta',
    message: ProposalUnitMismatch(proposalUnit).message,
  );
}

/// Whether [proposal] cannot be accepted because it was written for another unit.
bool unitMismatch(Proposal proposal, Settings settings) =>
    proposal.kind != Proposal.kindNoChange && proposal.unit != settings.unit;

/// A proposal screen whose proposal is not (or no longer) known on this device.
class MissingProposalScreen extends StatelessWidget {
  const MissingProposalScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      children: [
        ScreenHeader(title: title, leading: const BackChevron()),
        const EmptyState(icon: 'info', message: 'Esta propuesta ya no está disponible.'),
      ],
    ),
  );
}

/// `"Basado en tus últimas 12 sesiones · 3 ago – 28 sept"` ([recent]) or `"Basado en 12 sesiones
/// · …"`, or null without evidence.
String? evidenceLine(JsonMap? evidence, {bool recent = false}) {
  final sessions = asInt(evidence?['sessions']);
  if (sessions == null || sessions <= 0) return null;
  final from = asString(evidence?['from']);
  final to = asString(evidence?['to']);
  final range = from == null ? '' : ' · ${fmtDate(from)} – ${to == null ? '' : fmtDate(to)}';
  final base = switch ((recent, sessions)) {
    (true, 1) => 'Basado en tu última sesión',
    (true, _) => 'Basado en tus últimas $sessions sesiones',
    (false, 1) => 'Basado en 1 sesión',
    _ => 'Basado en $sessions sesiones',
  };
  return '$base$range';
}
