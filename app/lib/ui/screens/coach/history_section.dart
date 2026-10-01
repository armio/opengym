import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'coach_widgets.dart';

/// Log entries shown in the history list.
const historyLimit = 20;

/// "Historial del Coach": the newest [historyLimit] entries of `coach.log` (specs/coach.md
/// §7.8); each opens a detail sheet. Hidden while the log is empty.
class CoachHistorySection extends StatelessWidget {
  const CoachHistorySection({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.select<AppState, List<JsonMap>>((s) => s.coach.log);
    if (log.isEmpty) return const SizedBox.shrink();
    final entries = log.reversed.take(historyLimit).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption('Historial del Coach'),
          ItemList(
            children: [
              for (final e in entries)
                ListItem(
                  title: logEntryTitle(e),
                  subtitle: logEntrySubtitle(e),
                  trailing: const [Chevron()],
                  onTap: () => showLogEntrySheet(context, e),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `"30 sept · 2 aplicados"` (reviews), `"30 sept · descartada"`, or just the date.
String logEntrySubtitle(JsonMap entry) {
  final date = dateOfMs(asInt(entry['at']) ?? 0);
  if (entry['dismissed'] == true) return '$date · descartada';
  if (entry['kind'] != 'review') return date;
  final applied = appliedCount(entry);
  return '$date · ${applied == 1 ? '1 aplicado' : '$applied aplicados'}';
}

/// [decision] completed from its proposal for display. Declined and stale decisions are logged
/// without `target`/`before`/`after` (specs/coach.md §7.8), so their titles take the exercise
/// from the proposal's change when this device has it, and otherwise read "Ejercicio
/// desconocido" rather than a missing name.
JsonMap decisionForDisplay(JsonMap decision, Proposal? proposal) {
  final change = proposal?.changesJson.firstWhereOrNull((c) => c['id'] == decision['id']);
  final full = {...?change, ...decision};
  if (asMapOrNull(full['target']) == null) full['target'] = {'exId': unknownExerciseName};
  return full;
}

/// The detail of one log entry: summary, evidence, every decision with its tag, notes.
Future<void> showLogEntrySheet(BuildContext context, JsonMap entry) {
  final app = context.read<AppState>();
  final proposalId = asString(entry['proposalId']);
  return showAppSheet<void>(
    context,
    title: logEntryHeading(entry),
    builder: (_) => LogEntryDetail(
      entry: entry,
      names: DisplayNameIndex(app.exerciseIndex),
      proposal: proposalId == null ? null : app.proposalById(proposalId),
    ),
  );
}

class LogEntryDetail extends StatelessWidget {
  const LogEntryDetail({super.key, required this.entry, required this.names, this.proposal});

  final JsonMap entry;
  final ExerciseIndex names;

  /// The proposal the entry is about, when known: it fills in what declined decisions lack.
  final Proposal? proposal;

  @override
  Widget build(BuildContext context) {
    final t = context.textStyles;
    final summary = asString(entry['summary']) ?? '';
    final evidence = evidenceLine(asMapOrNull(entry['evidence']));
    final decisions = logDecisions(entry);
    final notes = asStringList(entry['notes']);
    final routines = asInt(entry['routines']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_dateLine(entry, routines), style: t.caption),
        if (summary.isNotEmpty) ...[const SizedBox(height: 10), ClaudeText(summary)],
        if (evidence != null) ...[const SizedBox(height: 10), Text(evidence, style: t.caption)],
        if (decisions.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final d in decisions) _DecisionRow(decision: decisionForDisplay(d, proposal), names: names),
        ],
        for (final n in notes) _NoteRow(text: n),
        const SizedBox(height: 10),
      ],
    );
  }

  static String _dateLine(JsonMap entry, int? routines) {
    final parts = [
      dateOfMs(asInt(entry['at']) ?? 0, long: true),
      if (entry['dismissed'] == true) 'descartada',
      if (entry['kind'] == 'create' && routines != null) routines == 1 ? '1 rutina' : '$routines rutinas',
      if ((asInt(entry['iteration']) ?? 1) > 1) 'revisión ${entry['iteration']}',
    ];
    return parts.join(' · ');
  }
}

class _DecisionRow extends StatelessWidget {
  const _DecisionRow({required this.decision, required this.names});

  final JsonMap decision;
  final ExerciseIndex names;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    final why = asString(decision['why']) ?? '';
    final status = decision['status'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.sep, width: .5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  capitalizeFirst(changeTitle(decision, names)),
                  style: t.small.copyWith(color: p.label, fontWeight: FontWeight.w600),
                ),
                if (why.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  ClaudeText(why, dim: true, style: t.small.copyWith(fontSize: 12, color: p.label3, height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tag(
            decisionLabel(status),
            capitalize: false,
            color: status == 'accepted' ? p.acc : (status == 'stale' ? p.yellow : p.label3),
          ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AppIcon('lightbulb', size: 15, color: context.palette.label3),
        ),
        const SizedBox(width: 8),
        Expanded(child: ClaudeText(text)),
      ],
    ),
  );
}
