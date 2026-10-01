import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../../engine/engine.dart';
import '../../widgets/widgets.dart';

/// An action of the plan tools sheet. The original's sheet shared, printed and imported plan
/// files, which the port does not carry (contract §6); it keeps the plan-wide actions that are
/// ported.
enum PlanTool { calendar, library, starterPlan, coach }

/// "Herramientas del plan" (specs/ui.md §4.13, ported actions only): the calendar, the exercise
/// library, the starter plan and the Coach. Resolves to the picked action — the caller runs it
/// once the sheet has closed — or null.
Future<PlanTool?> showPlanToolsSheet(BuildContext context) => showAppSheet<PlanTool>(
  context,
  title: 'Herramientas del plan',
  builder: (ctx) => _PlanTools(onPick: (tool) => Navigator.of(ctx).pop(tool)),
);

/// "Cargar plan inicial": Empuje / Tirón / Pierna on Monday, Wednesday and Friday. Routines that
/// already exist by name are reused rather than duplicated (data-B12).
void loadStarterPlanWithToast(BuildContext context) {
  final app = context.read<AppState>();
  app.updatePlan((plan) => loadStarterPlan(plan, now: app.clock.now()));
  showToast(context, starterPlanLoadedMessage);
}

class _PlanTools extends StatelessWidget {
  const _PlanTools({required this.onPick});

  final ValueChanged<PlanTool> onPick;

  @override
  Widget build(BuildContext context) {
    final exercises = context.select<AppState, int>((s) => s.catalog.length);
    return Section(
      children: [
        ListRow(
          icon: 'calendar',
          title: 'Calendario',
          subtitle: 'Tus entrenos del mes; toca un día para reprogramarlo',
          accessory: RowAccessory.chevron,
          onTap: () => onPick(PlanTool.calendar),
        ),
        ListRow(
          icon: 'magnifier',
          title: 'Biblioteca de ejercicios',
          subtitle: '$exercises ejercicios · crea los tuyos',
          accessory: RowAccessory.chevron,
          onTap: () => onPick(PlanTool.library),
        ),
        ListRow(
          icon: 'clipboard',
          title: 'Cargar plan inicial',
          subtitle: 'Empuje, Tirón y Pierna el lunes, miércoles y viernes. No duplica rutinas que ya tengas.',
          onTap: () => onPick(PlanTool.starterPlan),
        ),
        ListRow(
          icon: 'sparkles',
          title: 'Pide un plan a Claude',
          subtitle: 'Claude propone; tú lo aceptas en la pestaña Coach',
          accessory: RowAccessory.chevron,
          onTap: () => onPick(PlanTool.coach),
        ),
      ],
    );
  }
}
