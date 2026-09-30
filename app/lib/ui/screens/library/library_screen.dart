import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/library.dart';
import '../../shell.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'add_to_routine_sheet.dart';
import 'custom_exercise_sheet.dart';
import 'exercise_detail_sheet.dart';
import 'exercise_records.dart';

export 'add_to_routine_sheet.dart' show RoutineCreatedCallback, showAddToRoutineSheet;
export 'custom_exercise_sheet.dart' show confirmDeleteCustomExercise, createCustomExercise, showCustomExerciseSheet;
export 'exercise_detail_sheet.dart' show showExerciseDetailSheet;

/// The exercise library (specs/ui.md §3.8): search, body-part and equipment filters, custom
/// exercises first, pages of 40. A row opens the exercise detail; its "Plan" button adds the
/// exercise to a routine; the first row creates a custom exercise.
///
/// A routine created from here is reported to [onRoutineCreated]; by default the app switches
/// to the Plan tab, where the new routine is listed.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.onRoutineCreated});

  final RoutineCreatedCallback? onRoutineCreated;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _page = 40;

  String _query = '';

  /// Empty = every body part.
  String _bodyPart = '';

  /// Null = any equipment.
  String? _equipment;
  int _shown = _page;

  /// Applies a filter change and starts over at the first page.
  void _filter(VoidCallback change) => setState(() {
    change();
    _shown = _page;
  });

  RoutineCreatedCallback get _onRoutineCreated =>
      widget.onRoutineCreated ?? (_) => context.read<ShellController?>()?.goTo(AppTab.plan, popToRoot: true);

  void _openDetail(Exercise exercise) =>
      showExerciseDetailSheet(context, exercise, onRoutineCreated: _onRoutineCreated);

  Future<void> _createCustom() async {
    final created = await showCustomExerciseSheet(context, prefill: _query.trim());
    if (created != null && mounted) _openDetail(created);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final catalog = app.catalog;
    final search = catalog.search(query: _query, bodyPart: _bodyPart, equipment: _equipment);
    final results = search.results;
    final best = bestWeights(app.workouts, isCardio: catalog.isCardio);
    final navigator = Navigator.of(context);

    return Scaffold(
      body: PageBody(
        children: [
          ScreenHeader(
            title: 'Ejercicios',
            subtitle: '${catalog.library.builtIns.length} ejercicios con animaciones',
            leading: navigator.canPop()
                ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: navigator.pop)
                : null,
          ),
          SearchField(hint: 'Buscar…', onChanged: (v) => _filter(() => _query = v)),
          const SizedBox(height: 10),
          ChipsRow(
            children: [
              AppChip(
                'Todo',
                selected: _bodyPart.isEmpty,
                onTap: () => _filter(() {
                  _bodyPart = '';
                  _equipment = null;
                }),
              ),
              for (final bp in catalog.bodyParts)
                AppChip(
                  bodyPartLabel(bp),
                  selected: _bodyPart == bp,
                  onTap: () => _filter(() {
                    _bodyPart = bp;
                    _equipment = null;
                  }),
                ),
            ],
          ),
          if (search.equipmentOptions.length > 1) ...[
            const SizedBox(height: 8),
            ChipsRow(
              children: [
                AppChip(
                  'Cualquier equipo',
                  selected: search.equipment == null,
                  onTap: () => _filter(() => _equipment = null),
                ),
                for (final eq in search.equipmentOptions)
                  AppChip(
                    equipmentLabel(eq),
                    selected: search.equipment == eq,
                    onTap: () => _filter(() => _equipment = eq),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ItemList(
            children: [
              _CreateCustomRow(onTap: _createCustom),
              for (final ex in results.take(_shown))
                _LibraryRow(
                  exercise: ex,
                  best: best[ex.id] ?? 0,
                  onTap: () => _openDetail(ex),
                  onAdd: () => showAddToRoutineSheet(context, ex, onRoutineCreated: _onRoutineCreated),
                ),
            ],
          ),
          if (results.isEmpty) const EmptyState(icon: 'magnifier', message: 'Sin resultados'),
          if (results.length > _shown) ...[
            const SizedBox(height: 10),
            AppButton('Mostrar más', onPressed: () => setState(() => _shown += _page)),
          ],
        ],
      ),
    );
  }
}

/// "Crea tu propio ejercicio" — always the first row.
class _CreateCustomRow extends StatelessWidget {
  const _CreateCustomRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListItem(
    leading: const ExerciseThumb(placeholderIcon: 'sparkles'),
    title: 'Crea tu propio ejercicio',
    subtitle: 'nombre + parte del cuerpo, sin animación',
    trailing: [AppIcon('plus', size: 18, color: context.palette.label3)],
    onTap: onTap,
  );
}

/// An exercise with its best load (when there is one) and a "Plan" button.
class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.exercise, required this.best, required this.onTap, required this.onAdd});

  final Exercise exercise;
  final num best;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => ExerciseTile(
    exercise: exercise,
    onTap: onTap,
    trailing: [
      if (best > 0) Tag(formatNum(best), accent: true),
      AppButton('Plan', icon: 'plus', size: ButtonSize.sm, variant: ButtonVariant.tinted, onPressed: onAdd),
    ],
  );
}
