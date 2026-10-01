import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'workout_controller.dart';

/// The finish summary (specs/ui.md §5.11), locked so only "¡Genial!" closes it: duration,
/// volume, sets and records, the load and e1RM records, the muscles worked, and how it felt —
/// a rating (Fácil / Justo / Duro) and a note, both always offered and independent (contract
/// §2.1). They are written to the stored workout as they change.
Future<void> showFinishSummary(BuildContext context, FinishSummary summary) =>
    showAppSheet<void>(context, locked: true, builder: (_) => FinishSummarySheet(summary: summary));

/// Session ratings: the stored value and its label.
const sessionRatings = [('easy', 'Fácil'), ('right', 'Justo'), ('hard', 'Duro')];

/// The longest note kept.
const sessionNoteMax = 300;

/// The note as stored: trimmed, at most 300 characters, null when empty (the key is deleted).
String? normalizeSessionNote(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > sessionNoteMax ? trimmed.substring(0, sessionNoteMax) : trimmed;
}

class FinishSummarySheet extends StatefulWidget {
  const FinishSummarySheet({super.key, required this.summary});

  final FinishSummary summary;

  @override
  State<FinishSummarySheet> createState() => _FinishSummarySheetState();
}

class _FinishSummarySheetState extends State<FinishSummarySheet> {
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  String? _rating;

  String get _workoutId => widget.summary.workout.id;

  @override
  void initState() {
    super.initState();
    _noteFocus.addListener(() {
      if (!_noteFocus.hasFocus) _saveNote();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// Tapping the selected rating again clears it.
  void _rate(String value) {
    final next = value == _rating ? null : value;
    setState(() => _rating = next);
    context.read<AppState>().edit((d) => d.workout(_workoutId)?.rating = next);
  }

  void _saveNote() {
    final note = normalizeSessionNote(_note.text);
    final app = context.read<AppState>();
    if (app.workoutById(_workoutId)?.note == note) return;
    app.edit((d) => d.workout(_workoutId)?.note = note);
  }

  void _done() {
    _saveNote();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(child: AppIcon('trophy', size: 44, color: p.acc)),
        const SizedBox(height: 8),
        Text('¡Entrenamiento completado!', textAlign: TextAlign.center, style: t.sheetTitle),
        const SizedBox(height: 14),
        _SummaryTiles(summary: widget.summary),
        _RecordLines(summary: widget.summary),
        const SectionCaption('Lo que acabas de entrenar'),
        BodyMap(
          levels: widget.summary.muscleLevels,
          figure: context.select<AppState, String>((s) => s.settings.body),
          compact: true,
        ),
        const SectionCaption('¿Cómo te has sentido?'),
        _RatingPicker(value: _rating, onChanged: _rate),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          focusNode: _noteFocus,
          minLines: 2,
          maxLines: 4,
          inputFormatters: [LengthLimitingTextInputFormatter(sessionNoteMax)],
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: '¿Algo que merezca recordarse? (opcional)'),
        ),
        const SizedBox(height: 14),
        AppButton('¡Genial!', variant: ButtonVariant.primary, onPressed: _done),
      ],
    );
  }
}

class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.summary});

  final FinishSummary summary;

  @override
  Widget build(BuildContext context) {
    final unit = context.select<AppState, String>((s) => s.settings.unit);
    final w = summary.workout;
    final style = context.textStyles.statValue.copyWith(fontSize: 18);
    return TileGrid(
      tiles: [
        StatTile(label: 'Duración', value: fmtDur(w.end - w.start), valueStyle: style),
        StatTile(label: 'Volumen', value: fmtVol(w.vol, unit), valueStyle: style),
        StatTile(label: 'Series', value: '${setsDone(w)}', valueStyle: style),
        StatTile(
          label: 'Récords',
          value: w.prs.isEmpty ? '—' : '${w.prs.length}',
          valueStyle: style.copyWith(fontSize: 20),
        ),
      ],
    );
  }
}

/// "Nuevo récord: Press Banca" per load record, "Mejor 1RM estimado: Press Banca · 80 kg" per
/// e1RM record.
class _RecordLines extends StatelessWidget {
  const _RecordLines({required this.summary});

  final FinishSummary summary;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final unit = app.settings.unit;
    String name(String id) => capitalizeWords(app.catalog.exOr(id).name);
    final lines = [
      for (final id in summary.workout.prs) ('trophy', 'Nuevo récord: ${name(id)}'),
      for (final r in summary.e1rmRecords)
        ('chartLine', 'Mejor 1RM estimado: ${name(r.exerciseId)} · ${fmtVol(r.record.est, unit)}'),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    final color = context.palette.acc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AppIcon(icon, size: 13, color: color),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(text, style: context.textStyles.small.copyWith(color: color)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Three equal cells on a track; nothing selected until the owner picks one.
class _RatingPicker extends StatelessWidget {
  const _RatingPicker({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 36,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: p.segmentTrack, borderRadius: BorderRadius.circular(9)),
      child: Row(
        children: [
          for (final (key, label) in sessionRatings)
            Expanded(
              child: Semantics(
                button: true,
                selected: key == value,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(key),
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: key == value ? p.segmentThumb : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: key == value
                          ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: key == value ? FontWeight.w500 : FontWeight.w400,
                        color: key == value ? p.label : p.label2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
