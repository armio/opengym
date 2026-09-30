import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

/// PLACEHOLDER — owned by the Progress track, which replaces this file.
/// Progreso tab: stats and history (specs/ui.md §3.6–3.7).
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      children: [
        ScreenHeader(
          title: 'Progreso',
          leading: Navigator.of(context).canPop()
              ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: () => Navigator.of(context).pop())
              : null,
        ),
        const EmptyState(icon: 'clipboard', message: 'Pantalla en construcción.'),
      ],
    ),
  );
}
