import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/library.dart';
import '../theme.dart';
import 'app_icons.dart';
import 'buttons.dart';
import 'controls.dart';
import 'exercise_media.dart';
import 'exercise_tile.dart';
import 'sheets.dart';
import 'surfaces.dart';

/// Creates a custom exercise from the picker's "Crea tu propio ejercicio" row, prefilled with
/// the current search text; returns the new exercise (then treated as picked) or null.
typedef CreateCustomExercise = Future<Exercise?> Function(BuildContext context, String query);

/// Opens the exercise picker sheet (specs/ui.md §4.8): search (English names and Spanish
/// taxonomy, accent-insensitive), "★ Elegidos" / "Todo" / body-part chips, equipment chips,
/// pages of 50.
///
/// * Without [onPick] the sheet closes on the first pick and resolves to that exercise
///   (null when dismissed).
/// * With [onPick] it stays open (the original's multi-add): each pick awaits [onPick] — which
///   may open the config sheet on top — and the future resolves to null when dismissed.
///
/// The "Crea tu propio ejercicio" row is shown only when [onCreateCustom] is given.
Future<Exercise?> showExercisePicker(
  BuildContext context, {
  String title = 'Añadir ejercicio',
  CreateCustomExercise? onCreateCustom,
  FutureOr<void> Function(Exercise exercise)? onPick,
}) => showAppSheet<Exercise>(
  context,
  title: title,
  expand: true,
  builder: (ctx) => ExercisePickerBody(
    onCreateCustom: onCreateCustom,
    onPick: (ex) async {
      if (onPick == null) {
        Navigator.of(ctx).pop(ex);
      } else {
        await onPick(ex);
      }
    },
  ),
);

/// The picker's content, usable inside any bounded-height container.
class ExercisePickerBody extends StatefulWidget {
  const ExercisePickerBody({super.key, required this.onPick, this.onCreateCustom});

  final Future<void> Function(Exercise exercise) onPick;
  final CreateCustomExercise? onCreateCustom;

  @override
  State<ExercisePickerBody> createState() => _ExercisePickerBodyState();
}

/// The "★ Elegidos" filter value of [_ExercisePickerBodyState._bodyPart].
const _chosen = '★';

class _ExercisePickerBodyState extends State<ExercisePickerBody> {
  static const _page = 50;

  String _query = '';
  String _bodyPart = '';
  String? _equipment;
  int _shown = _page;

  void _filter(void Function() change) => setState(() {
    change();
    _shown = _page;
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final catalog = app.catalog;
    final usage = app.exerciseUsage();
    final chosen = _bodyPart == _chosen;
    final search = catalog.search(
      query: _query,
      bodyPart: chosen ? null : _bodyPart,
      equipment: _equipment,
      where: chosen ? (e) => (usage[e.id] ?? 0) > 0 : null,
      sort: chosen
          ? (a, b) {
              final byUse = (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
              return byUse != 0 ? byUse : a.name.compareTo(b.name);
            }
          : null,
    );
    final results = search.results;
    final p = context.palette;
    final showCreate = !chosen && widget.onCreateCustom != null;
    final extra = (showCreate ? 1 : 0) + (results.length > _shown ? 1 : 0);
    final listCount = results.length.clamp(0, _shown) + extra;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(hint: 'Buscar entre ${catalog.length} ejercicios…', onChanged: (v) => _filter(() => _query = v)),
        const SizedBox(height: 10),
        ChipsRow(
          children: [
            if (usage.isNotEmpty)
              AppChip(
                'Elegidos (${usage.length})',
                icon: 'starFill',
                selected: chosen,
                onTap: () => _filter(() {
                  _bodyPart = _chosen;
                  _equipment = null;
                }),
              ),
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
          const SizedBox(height: 6),
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
        const SizedBox(height: 10),
        Expanded(
          child: results.isEmpty && !showCreate
              ? EmptyState(
                  icon: chosen ? 'starFill' : 'magnifier',
                  message: chosen ? 'Nada elegido aún — añade ejercicios y aparecerán aquí.' : 'Sin resultados',
                )
              : ListView.separated(
                  itemCount: listCount,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (showCreate && i == 0) {
                      return ListItem(
                        leading: const ExerciseThumb(placeholderIcon: 'sparkles'),
                        title: 'Crea tu propio ejercicio',
                        subtitle: 'nombre + parte del cuerpo, sin animación',
                        trailing: [AppIcon('plus', size: 18, color: p.label3)],
                        onTap: () async {
                          final created = await widget.onCreateCustom!(context, _query.trim());
                          if (created != null) await widget.onPick(created);
                        },
                      );
                    }
                    final index = i - (showCreate ? 1 : 0);
                    if (index >= _shown || index >= results.length) {
                      return AppButton('Mostrar más', onPressed: () => setState(() => _shown += _page));
                    }
                    final ex = results[index];
                    return ExerciseTile(
                      exercise: ex,
                      trailing: [
                        if ((usage[ex.id] ?? 0) > 0) const Tag('', icon: 'starFill', accent: true),
                        AppIcon('plus', size: 18, color: p.label3),
                      ],
                      onTap: () => widget.onPick(ex),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
