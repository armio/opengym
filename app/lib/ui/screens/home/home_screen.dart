import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

/// PLACEHOLDER — owned by the Home track, which replaces this file.
/// Inicio tab: week strip, today, Coach card, body weight, streak (specs/ui.md §3.2).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      children: [
        ScreenHeader(
          title: 'Inicio',
          leading: Navigator.of(context).canPop()
              ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: () => Navigator.of(context).pop())
              : null,
        ),
        const EmptyState(icon: 'clipboard', message: 'Pantalla en construcción.'),
      ],
    ),
  );
}
