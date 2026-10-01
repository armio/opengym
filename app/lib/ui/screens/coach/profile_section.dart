import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/app_state.dart';
import '../../../data/models/models.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'coach_widgets.dart';
import 'intake_options.dart';
import 'intake_screen.dart';

/// Remembers the `savedAt` of the newest Claude edit of the athlete profile the owner has seen,
/// so the "Claude actualizó tu perfil" banner shows once per edit (device-local).
class ProfileSeenStore {
  const ProfileSeenStore();

  static const _key = 'coach.athleteSeenSavedAt';

  Future<int?> load() async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_key);
    } on Exception catch (e) {
      debugPrint('profile seen: $e');
      return null;
    }
  }

  Future<void> save(int savedAt) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(_key, savedAt);
    } on Exception catch (e) {
      debugPrint('profile seen: $e');
    }
  }
}

/// Opens the intake in edit mode.
Future<void> openAthleteIntake(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AthleteIntakeScreen()));

/// Who saved the profile last, for the row's subtitle.
String? _savedByLine(AthleteProfile a) {
  final at = a.savedAt;
  if (at == null) return null;
  return switch (a.updatedBy) {
    'claude' => 'Actualizado por Claude el ${dateOfMs(at)}',
    'import' => 'Importado de una copia el ${dateOfMs(at)}',
    _ => null,
  };
}

/// "Perfil de atleta": a summary of the intake answers; opens the intake in edit mode.
class AthleteProfileSection extends StatelessWidget {
  const AthleteProfileSection({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final athlete = context.select<AppState, AthleteProfile>((s) => s.athlete);
    final savedBy = _savedByLine(athlete);
    return Section(
      title: 'Perfil de atleta',
      footer: 'Claude lo usa en cada propuesta y también puede actualizarlo. Mantén al día tus limitaciones.',
      children: [
        ListRow(
          icon: 'person',
          iconTint: context.palette.indigo,
          title: 'Tus respuestas',
          subtitle: [athleteSummary(athlete), ?savedBy].join('\n'),
          accessory: RowAccessory.chevron,
          onTap: onOpen,
        ),
      ],
    );
  }
}

/// "Claude actualizó tu perfil" (contract §6.4): shown while the profile's last save is
/// Claude's and the owner has not seen that save yet.
class ClaudeProfileBanner extends StatelessWidget {
  const ClaudeProfileBanner({super.key, required this.athlete, required this.onOpen, required this.onDismiss});

  final AthleteProfile athlete;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  /// Whether [athlete] carries a Claude edit newer than [seenSavedAt].
  static bool isDue(AthleteProfile athlete, int? seenSavedAt) =>
      athlete.updatedBy == 'claude' && athlete.savedAt != null && athlete.savedAt != seenSavedAt;

  @override
  Widget build(BuildContext context) => NoticeCard(
    icon: 'sparkles',
    tint: context.palette.acc,
    title: 'Claude actualizó tu perfil',
    message:
        'El ${dateOfMs(athlete.savedAt ?? 0, long: true)}: ${athleteSummary(athlete)}. '
        'Revísalo por si algo no encaja.',
    actions: [AppButton('Ver perfil', size: ButtonSize.sm, variant: ButtonVariant.tinted, onPressed: onOpen)],
    onClose: onDismiss,
  );
}
