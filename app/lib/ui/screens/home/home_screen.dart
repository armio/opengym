import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../widgets/widgets.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';
import 'body_weight_card.dart';
import 'coach_card.dart';
import 'streak_card.dart';
import 'today_card.dart';
import 'week_card.dart';

/// Inicio (specs/ui.md §3.2): what to do now and a quick glance — the workout in progress or
/// today's session, Claude's pending proposals, the week, body weight and the streak. The header
/// holds the sync state, the exercise library and Ajustes; pulling down syncs.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    void push(Widget screen) => navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
    return Scaffold(
      body: PageBody(
        onRefresh: app.sync,
        children: [
          ScreenHeader(
            title: 'openGym',
            subtitle: capitalizeFirst(formatDateFull(app.clock.now())),
            actions: [
              const SyncStatusIndicator(),
              AppIconButton(
                icon: 'list',
                tooltip: 'Biblioteca de ejercicios',
                onPressed: () => push(const LibraryScreen()),
              ),
              AppIconButton(icon: 'gear', tooltip: 'Ajustes', onPressed: () => push(const SettingsScreen())),
            ],
          ),
          const TodaySection(),
          const CoachCard(),
          const WeekCard(),
          const BodyWeightCard(),
          const StreakCard(),
        ],
      ),
    );
  }
}
