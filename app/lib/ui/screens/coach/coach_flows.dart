import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/api_client.dart';
import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../shell.dart';
import '../../widgets/widgets.dart';

/// The Coach's online writes (contract §4.3, draft → commit): each one builds its result on a
/// [ProposalDraft] with the engine (specs/coach.md §7) and sends it with the proposal's
/// resolution in one atomic request. When the engine throws, nothing is sent; when the server
/// answers 409 or cannot be reached, [AppState] keeps the local docs untouched, pulls, and the
/// error propagates. Nothing is queued offline.
class CoachFlows {
  CoachFlows(this.app);

  final AppState app;

  DateTime get _now => app.clock.now();

  /// "Aceptar plan": adds the bundle's routines as new ones and, with [schedule], replaces the
  /// weekly schedule.
  Future<void> acceptPlan(Proposal proposal, {required bool schedule}) async {
    final draft = app.beginProposalDraft();
    applyCreatedPlan(draft.plan, draft.coach, proposal, schedule: schedule, now: _now);
    await app.resolveProposal(proposal, outcome: 'applied', accepted: const ['plan'], schedule: schedule, draft: draft);
  }

  /// "Descartar" a plan: logged so Claude knows it was turned down.
  Future<void> dismissPlan(Proposal proposal) async {
    final draft = app.beginProposalDraft();
    recordDismissal(draft.coach, proposal, now: _now);
    await app.resolveProposal(proposal, outcome: 'dismissed', rejected: const ['plan'], draft: draft);
  }

  /// "Aplicar N cambios": applies the [ticked] changes that still fit the plan. Returns what
  /// was applied; an empty result sent nothing (the caller runs the dismiss flow instead).
  Future<ChangeSetResult> applyChanges(Proposal proposal, Set<String> ticked) async {
    final draft = app.beginProposalDraft();
    final result = applyChangeSet(draft.plan, draft.coach, proposal, ticked, library: app.exerciseIndex, now: _now);
    if (result.isEmpty) return result;
    await app.resolveProposal(
      proposal,
      outcome: 'applied',
      accepted: result.applied,
      rejected: result.rejected,
      stale: result.stale,
      draft: draft,
    );
    return result;
  }

  /// "Descartar todo": every applicable change is declined; the stale ones are reported as such.
  Future<void> dismissChanges(Proposal proposal) async {
    final draft = app.beginProposalDraft();
    final reviewed = markStale(proposal, draft.plan, app.exerciseIndex);
    final stale = {
      for (final c in reviewed.changes)
        if (c.stale) c.id,
    };
    recordDismissal(draft.coach, proposal, stale: stale, now: _now);
    await app.resolveProposal(
      proposal,
      outcome: 'dismissed',
      rejected: [for (final c in reviewed.applicable) c.id],
      stale: [...stale],
      draft: draft,
    );
  }

  /// "Entendido" on a reading: acknowledged without touching any doc.
  Future<void> acknowledge(Proposal proposal) => app.resolveProposal(proposal, outcome: 'dismissed');

  /// "Deshacer los últimos cambios del Coach": restores the newest snapshot and reverts its
  /// proposal on the server. Returns false when there was nothing to undo.
  Future<bool> undoLast() async {
    final draft = app.beginProposalDraft();
    final snapshot = revertLast(draft.plan, draft.coach, now: _now);
    if (snapshot == null) return false;
    final id = snapshot.proposalId;
    if (id == null || id.isEmpty) {
      throw const ProposalException('Estos cambios no vienen de ninguna propuesta: no se pueden deshacer desde aquí.');
    }
    // The server only needs the id; a proposal this device never pulled still reverts.
    await app.revertProposal(app.proposalById(id) ?? Proposal(id: id, kind: '', status: 'applied'), draft);
    return true;
  }
}

/// Why an online Coach write failed, in Spanish; every failure leaves local data untouched.
String coachErrorText(Object error) => switch (error) {
  ProposalUnitMismatch() => error.message,
  ProposalException() => error.message,
  OfflineException() => 'Sin conexión con tu servidor: no se ha cambiado nada. Inténtalo con conexión.',
  ConflictException() => '${error.message} Se muestra el estado del servidor.',
  ApiException() => 'No se pudo completar: ${error.message}',
  _ => 'Algo salió mal: no se ha cambiado nada.',
};

/// Runs [write]; on failure shows why as a toast and returns false.
Future<bool> runCoachWrite(BuildContext context, Future<void> Function() write) async {
  try {
    await write();
    return true;
  } catch (e, stack) {
    // Malformed proposal data can surface as an Error from the engine; the draft is discarded
    // either way, so report it like any other failure.
    debugPrint('coach write failed: $e\n$stack');
    if (context.mounted) showToast(context, coachErrorText(e));
    return false;
  }
}

/// Leaves a pushed proposal screen: back to the Coach list, or on to [tab] (the Plan tab after
/// accepting, as the original does).
void leaveProposal(BuildContext context, {AppTab? tab}) {
  final shell = context.read<ShellController?>();
  Navigator.of(context).maybePop();
  if (tab != null) shell?.goTo(tab, popToRoot: true);
}
