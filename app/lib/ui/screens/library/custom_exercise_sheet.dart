import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/clock.dart';
import '../../../data/library.dart';
import '../../../data/models/models.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';

/// Longest custom-exercise description kept.
const customDescriptionMaxLength = 1000;

/// Why a custom exercise cannot be saved, or null when it can (data-model §2.5.5 / ui §4.7).
///
/// [name] is the trimmed name; another exercise — built-in or custom, other than [selfId] — with
/// the same name, case-insensitively, is a duplicate.
String? validateCustomExercise(ExerciseCatalog catalog, {required String name, String? bodyPart, String? selfId}) {
  if (name.isEmpty) return 'Ponle un nombre';
  if (bodyPart == null || bodyPart.isEmpty) return 'Elige una parte del cuerpo';
  final lower = name.toLowerCase();
  for (final e in catalog.all) {
    if (e.id != selfId && e.name.toLowerCase() == lower) return '«${capitalizeWords(e.name)}» ya existe';
  }
  return null;
}

/// "Crea tu propio ejercicio" / "Editar ejercicio propio" (specs/ui.md §4.7): name, body part and
/// an optional description. Resolves to the saved exercise, or null when dismissed. Editing
/// offers "Eliminar ejercicio" (→ [confirmDeleteCustomExercise]).
///
/// [prefill] seeds the name of a new exercise (the library/picker search text).
Future<Exercise?> showCustomExerciseSheet(BuildContext context, {Exercise? existing, String prefill = ''}) async {
  final result = await showAppSheet<_CustomSheetResult>(
    context,
    builder: (_) => _CustomExerciseForm(existing: existing, prefill: prefill),
  );
  if (result == null || !context.mounted) return null;
  switch (result) {
    case _Saved(:final id):
      return context.read<AppState>().catalog.byId(id);
    case _DeleteRequested():
      await confirmDeleteCustomExercise(context, existing!);
      return null;
  }
}

/// [showCustomExerciseSheet] for a new exercise, shaped as the exercise picker's
/// `onCreateCustom` hook.
Future<Exercise?> createCustomExercise(BuildContext context, String query) =>
    showCustomExerciseSheet(context, prefill: query);

/// `deleteCustomEx` (specs/ui.md §4.7): refuses while the active workout uses the exercise,
/// asks for confirmation, then removes it from the plan and every routine, stamps its name into
/// past workouts and drops its working weight ([AppState.deleteCustomExercise]). Resolves to
/// true when it was deleted.
Future<bool> confirmDeleteCustomExercise(BuildContext context, Exercise exercise) async {
  final app = context.read<AppState>();
  const busy = 'Termina primero tu entrenamiento actual';
  if (app.active?.entries.any((e) => e.id == exercise.id) ?? false) {
    showToast(context, busy);
    return false;
  }
  final confirmed = await showConfirm(
    context,
    title: '¿Eliminar «${capitalizeWords(exercise.name)}»?',
    message: 'Se quitará de tus rutinas. Los entrenamientos ya registrados conservan sus series.',
    confirmText: 'Eliminar',
    danger: true,
  );
  if (!confirmed || !context.mounted) return false;
  final deleted = app.deleteCustomExercise(exercise.id);
  showToast(context, deleted ? 'Ejercicio eliminado' : busy);
  return deleted;
}

sealed class _CustomSheetResult {
  const _CustomSheetResult();
}

class _Saved extends _CustomSheetResult {
  const _Saved(this.id);

  final String id;
}

class _DeleteRequested extends _CustomSheetResult {
  const _DeleteRequested();
}

class _CustomExerciseForm extends StatefulWidget {
  const _CustomExerciseForm({required this.existing, required this.prefill});

  final Exercise? existing;
  final String prefill;

  @override
  State<_CustomExerciseForm> createState() => _CustomExerciseFormState();
}

class _CustomExerciseFormState extends State<_CustomExerciseForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? widget.prefill);
  late final _description = TextEditingController(text: widget.existing?.desc ?? '');
  late String? _bodyPart = widget.existing?.bodyPart;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final app = context.read<AppState>();
    final name = _name.text.trim();
    final error = validateCustomExercise(app.catalog, name: name, bodyPart: _bodyPart, selfId: widget.existing?.id);
    if (error != null) {
      showToast(context, error);
      return;
    }
    final bodyPart = _bodyPart!;
    final desc = _description.text.trim();
    final description = desc.length > customDescriptionMaxLength ? desc.substring(0, customDescriptionMaxLength) : desc;
    final id = widget.existing?.id ?? 'c${uid(app.clock)}';
    app.updatePlan((plan) {
      final custom = plan.customById(id);
      if (custom == null) {
        plan.customEx.add(CustomExercise(id: id, n: name, bp: bodyPart, desc: description));
      } else {
        custom
          ..n = name
          ..bp = bodyPart
          ..desc = description;
      }
    });
    showToast(context, _editing ? 'Guardado' : '«$name» creado');
    Navigator.of(context).pop(_Saved(id));
  }

  @override
  Widget build(BuildContext context) {
    final bodyParts = context.select<AppState, List<String>>((s) => s.catalog.bodyParts);
    final p = context.palette;
    final t = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(_editing ? 'Editar ejercicio propio' : 'Crea tu propio ejercicio'),
        Text(
          'Ponle nombre y elige una parte del cuerpo — funciona como cualquier otro ejercicio, solo que sin animación.',
          style: t.small,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autofocus: !_editing && widget.prefill.isEmpty,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: 'Nombre del ejercicio'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final bp in bodyParts)
              AppChip(bodyPartLabel(bp), selected: _bodyPart == bp, onTap: () => setState(() => _bodyPart = bp)),
          ],
        ),
        const SizedBox(height: 12),
        if (_bodyPart == 'cardio') ...[
          Row(
            children: [
              AppIcon('figureRun', size: 14, color: p.label3),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Los ejercicios de cardio registran tiempo + velocidad en vez de peso × reps.',
                  style: t.small.copyWith(color: p.label3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _description,
          minLines: 4,
          maxLines: 4,
          maxLength: customDescriptionMaxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Descripción (opcional) — preparación, consejos, lo que quieras recordar',
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        AppButton(_editing ? 'Guardar' : 'Crear ejercicio', variant: ButtonVariant.primary, onPressed: _save),
        if (_editing) ...[
          const SizedBox(height: 8),
          AppButton(
            'Eliminar ejercicio',
            icon: 'trash',
            variant: ButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(const _DeleteRequested()),
          ),
        ],
      ],
    );
  }
}
