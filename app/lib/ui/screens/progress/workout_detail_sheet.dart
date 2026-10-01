import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'progress_data.dart';

/// The workout detail sheet (specs/ui.md §4.15): name, date · duration · volume · body weight,
/// how the session felt and its note (both editable), every exercise with its PR badge, done
/// sets (with effort), and the target it was prescribed, then "Eliminar entrenamiento".
///
/// Deleting confirms first and never recomputes working weights or other workouts' PRs
/// (data-B10). Matches the Plan calendar's `WorkoutDetailOpener`.
Future<void> showWorkoutDetailSheet(BuildContext context, Workout workout) =>
    showAppSheet<void>(context, builder: (_) => _WorkoutDetail(id: workout.id));

class _WorkoutDetail extends StatelessWidget {
  const _WorkoutDetail({required this.id});

  final String id;

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirm(
      context,
      title: '¿Eliminar entrenamiento?',
      message: 'Se elimina de tu historial para siempre.',
      confirmText: 'Eliminar',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    context.read<AppState>().deleteWorkout(id);
    Navigator.of(context).pop();
    showToast(context, 'Entrenamiento eliminado');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final w = app.workoutById(id);
    if (w == null) return const SizedBox.shrink();
    final unit = app.settings.unit;
    final subtitle = [
      fmtDate(w.d, long: true),
      ...durPart(w.end - w.start),
      fmtVol(w.vol, unit),
      if (w.bw != null) fmtVol(w.bw!, unit),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(w.name),
        Text(subtitle, style: context.textStyles.small),
        const SectionCaption('¿Cómo te has sentido?'),
        _RatingPicker(workoutId: id, rating: w.rating),
        const SizedBox(height: 8),
        _NoteField(key: ValueKey('note-$id'), workoutId: id, note: w.note),
        const SectionCaption('Ejercicios'),
        if (w.entries.isEmpty) Text('sin series', style: context.textStyles.small),
        for (final e in w.entries) _EntryBlock(entry: e, pr: w.prs.contains(e.id), unit: unit),
        const SizedBox(height: 10),
        AppButton(
          'Eliminar entrenamiento',
          icon: 'trash',
          variant: ButtonVariant.danger,
          onPressed: () => _delete(context),
        ),
      ],
    );
  }
}

/// Edits one finished workout in place.
void _editWorkout(AppState app, String id, void Function(Workout w) change) => app.edit((d) {
  final w = d.workout(id);
  if (w != null) change(w);
});

/// "Muy fácil · Bien · Brutal"; tapping the current one clears it.
class _RatingPicker extends StatelessWidget {
  const _RatingPicker({required this.workoutId, required this.rating});

  final String workoutId;
  final String? rating;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: [
      for (final MapEntry(key: value, value: label) in ratingLabels.entries)
        AppChip(
          label,
          icon: ratingIcons[value],
          capitalize: false,
          selected: rating == value,
          onTap: () {
            final next = rating == value ? null : value;
            _editWorkout(context.read<AppState>(), workoutId, (w) => w.rating = next);
          },
        ),
    ],
  );
}

/// The session note: trimmed, at most 300 characters, removed when empty; saved when the
/// field loses focus or the sheet closes.
class _NoteField extends StatefulWidget {
  const _NoteField({super.key, required this.workoutId, required this.note});

  final String workoutId;
  final String? note;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  static const maxLength = 300;

  late final _controller = TextEditingController(text: widget.note ?? '');
  final _focus = FocusNode();
  late final AppState _app = context.read<AppState>();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  /// Trimmed, capped, null when empty — how a note is stored.
  static String? _clean(String? text) {
    final v = (text ?? '').trim();
    if (v.isEmpty) return null;
    return v.length > maxLength ? v.substring(0, maxLength) : v;
  }

  bool get _changed => _clean(_controller.text) != _clean(widget.note);

  void _save() {
    if (!_changed) return;
    final value = _clean(_controller.text);
    _editWorkout(_app, widget.workoutId, (w) => w.note = value);
  }

  @override
  void didUpdateWidget(_NoteField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.note != old.note) _controller.text = widget.note ?? '';
  }

  @override
  void dispose() {
    // Closing the sheet mid-edit still keeps the note; the write waits until the tree is
    // unlocked, since it notifies listeners.
    if (_focus.hasFocus && _changed) {
      final value = _clean(_controller.text), app = _app, id = widget.workoutId;
      scheduleMicrotask(() => _editWorkout(app, id, (w) => w.note = value));
    }
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      minLines: 2,
      maxLines: 5,
      maxLength: maxLength,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => currentLength < 250
          ? null
          : Text('$currentLength/$maxLength', style: TextStyle(color: p.label3, fontSize: 11)),
      textCapitalization: TextCapitalization.sentences,
      style: context.textStyles.body.copyWith(fontSize: 15),
      cursorColor: p.acc,
      onTapOutside: (_) => _focus.unfocus(),
      decoration: InputDecoration(
        hintText: '¿Algo que merezca recordarse? (opcional)',
        hintStyle: TextStyle(color: p.label3),
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.r), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.r), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.r),
          borderSide: BorderSide(color: p.acc, width: 2),
        ),
      ),
    );
  }
}

/// One exercise of the workout: thumbnail, name with its PR badge, the done sets and the
/// prescribed target.
class _EntryBlock extends StatelessWidget {
  const _EntryBlock({required this.entry, required this.pr, required this.unit});

  final WorkoutEntry entry;
  final bool pr;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = context.textStyles;
    final exercise = app.catalog.byId(entry.id);
    final name = exercise?.name ?? entry.n ?? entry.id;
    final target = entry.targetConfig;
    final index = app.exerciseIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exercise != null) ...[ExerciseThumb(exercise: exercise), const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(capitalizeWords(name), style: t.itemTitle.copyWith(fontWeight: FontWeight.w600)),
                    if (pr) const PrBadge(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(doneSetsLine(index, entry), style: t.caption),
                if (target != null)
                  Text(
                    'Objetivo: ${exLine(index, target, unit)}',
                    style: t.caption.copyWith(color: context.palette.label3),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
