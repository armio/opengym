import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';
import 'about_section.dart';
import 'account_section.dart';
import 'backup_files.dart';
import 'claude_section.dart';
import 'data_section.dart';
import 'health_section.dart';
import 'preference_sections.dart';

export 'backup_files.dart' show BackupFiles, PlatformBackupFiles;

/// Ajustes (specs/ui.md §3.9, contract §6): account and devices, the Claude connector, Apple
/// Health (§8), preferences (bound to [AppState.updateSettings]), backups and "Borrar todo", and credits.
///
/// [backupFiles] picks and shares backup files (replaceable in tests).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.backupFiles = const PlatformBackupFiles()});

  final BackupFiles backupFiles;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    return Scaffold(
      body: PageBody(
        children: [
          ScreenHeader(
            title: 'Ajustes',
            leading: navigator.canPop()
                ? AppIconButton(icon: 'chevronLeft', tooltip: 'Atrás', onPressed: navigator.pop)
                : null,
            actions: const [SyncStatusIndicator()],
          ),
          const AccountSection(),
          const ConnectClaudeSection(),
          const HealthSection(),
          const GeneralSection(),
          const WorkoutSection(),
          const AppearanceSection(),
          DataSection(files: backupFiles),
          const AboutSection(),
        ],
      ),
    );
  }
}
