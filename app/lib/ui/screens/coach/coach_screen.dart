import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

/// PLACEHOLDER — owned by the Coach track, which replaces this file.
/// Coach tab: proposals, history, athlete profile, connect Claude (contract §6).
class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      children: [
        ScreenHeader(
          title: 'Coach',
          leading: Navigator.of(context).canPop()
              ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: () => Navigator.of(context).pop())
              : null,
        ),
        const EmptyState(icon: 'clipboard', message: 'Pantalla en construcción.'),
      ],
    ),
  );
}
