import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'coach_flows.dart';
import 'coach_widgets.dart';

/// "Deshacer los últimos cambios del Coach" (specs/coach.md §7.9): shown while a snapshot
/// exists; each tap restores the newest one (up to three steps back). Online only.
class UndoSection extends StatefulWidget {
  const UndoSection({super.key});

  @override
  State<UndoSection> createState() => _UndoSectionState();
}

class _UndoSectionState extends State<UndoSection> {
  bool _busy = false;

  Future<void> _undo() async {
    final confirmed = await showConfirm(
      context,
      title: '¿Deshacer los últimos cambios del Coach?',
      message:
          'Tu plan vuelve a como estaba antes de aceptarlos. Los entrenamientos registrados desde '
          'entonces no se tocan.',
      confirmText: 'Deshacer',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    var undone = false;
    final ok = await runCoachWrite(context, () async {
      undone = await CoachFlows(context.read<AppState>()).undoLast();
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) showToast(context, undone ? 'Plan restaurado' : 'Nada que deshacer');
  }

  @override
  Widget build(BuildContext context) {
    final coach = context.select<AppState, CoachDoc>((s) => s.coach);
    if (!canRevert(coach)) return const SizedBox.shrink();
    final last = coach.snapshots.last;
    final p = context.palette;
    return Section(
      title: 'Controles',
      children: [
        ListRow(
          icon: 'reset',
          iconTint: p.blue,
          title: 'Deshacer los últimos cambios del Coach',
          subtitle: [if (last.label.isNotEmpty) last.label, dateOfMs(last.at)].join(' · '),
          trailing: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          accessory: _busy ? RowAccessory.none : RowAccessory.chevron,
          onTap: _busy ? null : _undo,
        ),
      ],
    );
  }
}
