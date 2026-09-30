import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

/// PLACEHOLDER — owned by the Plan track, which replaces this file.
/// Plan tab: week schedule, routines, routine editor (specs/ui.md §3.3–3.4).
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      children: [
        ScreenHeader(
          title: 'Plan',
          leading: Navigator.of(context).canPop()
              ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: () => Navigator.of(context).pop())
              : null,
        ),
        const EmptyState(icon: 'clipboard', message: 'Pantalla en construcción.'),
      ],
    ),
  );
}
