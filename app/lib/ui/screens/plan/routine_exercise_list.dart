import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'routine_editing.dart';

/// The routine editor's exercise list (specs/ui.md §3.4): one row per entry in plan order, a
/// "Superserie" label above each multi-member superset, an accent bar on its members, and per
/// row the link / move controls. Unknown ids show as "Ejercicio desconocido" so they stay
/// visible and deletable.
class RoutineExerciseList extends StatelessWidget {
  const RoutineExerciseList({
    super.key,
    required this.routine,
    required this.onOpen,
    required this.onToggleLink,
    required this.onMove,
  });

  final Routine routine;

  /// Tap on entry `i` (opens its config sheet).
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onToggleLink;

  /// `(i, dir)`: move entry `i` up (−1) or down (+1).
  final void Function(int i, int dir) onMove;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final index = app.exerciseIndex;
    final ex = routine.ex;
    final layout = supersetLayout(ex);
    return ItemList(
      children: [
        for (var i = 0; i < ex.length; i++)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (layout.firsts.contains(i)) const _SupersetLabel(),
              ExerciseTile(
                exercise: app.catalog.exOr(ex[i].id),
                subtitle: exLine(index, ex[i], app.settings.unit),
                accentBar: layout.members.contains(i),
                onTap: () => onOpen(i),
                trailing: [
                  _RowControls(
                    canLink: i > 0,
                    linked: isLinkedToPrevious(ex, i),
                    onToggleLink: () => onToggleLink(i),
                    onUp: () => onMove(i, -1),
                    onDown: () => onMove(i, 1),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

/// "Superserie" with a link icon, in the accent (`.ss-label`).
class _SupersetLabel extends StatelessWidget {
  const _SupersetLabel();

  @override
  Widget build(BuildContext context) {
    final acc = context.palette.acc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 5),
      child: Row(
        children: [
          AppIcon('link', size: 13, color: acc),
          const SizedBox(width: 5),
          Text(
            'Superserie',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: -.05, color: acc),
          ),
        ],
      ),
    );
  }
}

/// The link button (from the second row on) above the move up / move down pair.
class _RowControls extends StatelessWidget {
  const _RowControls({
    required this.canLink,
    required this.linked,
    required this.onToggleLink,
    required this.onUp,
    required this.onDown,
  });

  final bool canLink;
  final bool linked;
  final VoidCallback onToggleLink;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (canLink) ...[
        _MiniButton(
          icon: 'link',
          label: 'Superserie con el ejercicio de arriba',
          width: 32,
          height: 28,
          radius: 8,
          iconSize: 15,
          selected: linked,
          onTap: onToggleLink,
        ),
        const SizedBox(height: 2),
      ],
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniButton(icon: 'chevronUp', label: 'Subir', onTap: onUp),
          const SizedBox(width: 2),
          _MiniButton(icon: 'chevronDown', label: 'Bajar', onTap: onDown),
        ],
      ),
    ],
  );
}

/// A small rectangular icon button (`.iconbtn` resized); [selected] is the `on-ss` tint.
class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.width = 28,
    this.height = 24,
    this.radius = 7,
    this.iconSize = 12,
    this.selected = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double radius;
  final double iconSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: label,
      child: Semantics(
        selected: selected,
        child: Pressable(
          onTap: onTap,
          pressedScale: .92,
          color: selected ? p.accSoft : p.surface,
          pressedColor: p.surface2,
          borderRadius: BorderRadius.circular(radius),
          semanticLabel: label,
          child: SizedBox(
            width: width,
            height: height,
            child: Center(
              child: AppIcon(icon, size: iconSize, color: selected ? p.acc : p.label),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Qué trabaja esta sesión": the routine's planned sets on the body map (the owner's figure)
/// and its six most-worked muscles.
class RoutineCoverageCard extends StatelessWidget {
  const RoutineCoverageCard({super.key, required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = loadOfRoutine(app.exerciseIndex, routine);
    final worked = rankOf(load).worked;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle('Qué trabaja esta sesión'),
          BodyMap(levels: levelsOf(load), figure: app.settings.body),
          if (worked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 6, runSpacing: 6, children: [for (final m in worked.take(6)) MuscleChip(m)]),
            ),
        ],
      ),
    );
  }
}
