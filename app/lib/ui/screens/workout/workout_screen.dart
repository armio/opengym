import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

/// PLACEHOLDER — owned by the Workout track, which replaces this file.
/// Start chooser and the guided active workout (specs/ui.md §3.5, §5).
class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      children: [
        ScreenHeader(
          title: 'Entrenar',
          leading: Navigator.of(context).canPop()
              ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: () => Navigator.of(context).pop())
              : null,
        ),
        const EmptyState(icon: 'clipboard', message: 'Pantalla en construcción.'),
      ],
    ),
  );
}
