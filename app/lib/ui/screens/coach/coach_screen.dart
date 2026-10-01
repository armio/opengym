import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_state.dart';
import '../../widgets/widgets.dart';
import 'coach_widgets.dart';
import 'connect_section.dart';
import 'history_section.dart';
import 'pending_section.dart';
import 'profile_section.dart';
import 'undo_section.dart';

/// The Coach tab (contract §6): where the owner decides on Claude's proposals.
///
/// Pending proposals (or an empty state), "Deshacer los últimos cambios del Coach", the athlete
/// profile (with the "Claude actualizó tu perfil" banner), the decision history and how to
/// connect Claude. Accepting, dismissing and undoing are online only.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, this.seenStore = const ProfileSeenStore()});

  /// Where the last seen Claude edit of the profile is remembered.
  final ProfileSeenStore seenStore;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  int? _seenSavedAt;
  bool _seenLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSeen());
  }

  Future<void> _loadSeen() async {
    final seen = await widget.seenStore.load();
    if (!mounted) return;
    setState(() {
      _seenSavedAt = seen;
      _seenLoaded = true;
    });
  }

  void _markSeen() {
    final savedAt = context.read<AppState>().athlete.savedAt;
    if (savedAt == null || savedAt == _seenSavedAt) return;
    setState(() => _seenSavedAt = savedAt);
    unawaited(widget.seenStore.save(savedAt));
  }

  void _openProfile() {
    _markSeen();
    unawaited(openAthleteIntake(context));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final athlete = app.athlete;
    // Before anything has happened, how to connect Claude is what matters most.
    final newcomer = app.pendingProposals.isEmpty && app.coach.log.isEmpty;
    final navigator = Navigator.of(context);
    return Scaffold(
      body: PageBody(
        onRefresh: app.sync,
        children: [
          ScreenHeader(
            title: 'Coach',
            subtitle: 'Claude propone; tú decides',
            leading: navigator.canPop() ? const BackChevron() : null,
            actions: const [SyncStatusIndicator()],
          ),
          const CoachOfflineNotice(),
          if (_seenLoaded && ClaudeProfileBanner.isDue(athlete, _seenSavedAt))
            ClaudeProfileBanner(athlete: athlete, onOpen: _openProfile, onDismiss: _markSeen),
          const PendingProposalsSection(),
          if (newcomer) const CoachConnectSection(),
          const UndoSection(),
          AthleteProfileSection(onOpen: _openProfile),
          const CoachHistorySection(),
          if (!newcomer) const CoachConnectSection(),
        ],
      ),
    );
  }
}
