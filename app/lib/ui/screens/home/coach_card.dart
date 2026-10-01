import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../shell.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';

/// "N propuestas de Claude" while any proposal waits for a decision (contract §6); opens the
/// Coach tab. Nothing otherwise.
class CoachCard extends StatelessWidget {
  const CoachCard({super.key});

  @override
  Widget build(BuildContext context) {
    final pending = context.select<AppState, int>((s) => s.pendingProposals.length);
    if (pending == 0) return const SizedBox.shrink();
    final p = context.palette;
    final t = context.textStyles;
    return AppCard(
      border: Border.all(color: p.acc, width: .5),
      onTap: () => context.read<ShellController?>()?.goTo(AppTab.coach, popToRoot: true),
      child: Row(
        children: [
          const IconBadge(icon: 'sparkles'),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('COACH', style: t.microCaps),
                const SizedBox(height: 2),
                Text(
                  pending == 1 ? '1 propuesta de Claude' : '$pending propuestas de Claude',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.rowTitle.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Tag('Revisar', accent: true),
        ],
      ),
    );
  }
}
