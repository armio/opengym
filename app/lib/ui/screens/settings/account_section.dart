import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/api_client.dart';
import '../../../data/app_state.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'devices_sheet.dart';

/// "Cuenta": the server, this device and its sync state, the other devices, revoking Claude's
/// access and signing out (contract §4.6).
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  Future<void> _revokeClaude(BuildContext context) async {
    final confirmed = await showConfirm(
      context,
      title: '¿Revocar el acceso de Claude?',
      message:
          'Claude dejará de poder leer tus entrenos y proponer cambios. Para volver a usarlo, '
          'conéctalo de nuevo desde Claude.',
      confirmText: 'Revocar',
      danger: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await context.read<AppState>().revokeClaudeAccess();
      if (context.mounted) showToast(context, 'Acceso de Claude revocado');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, 'No se pudo revocar: ${e.message}');
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showConfirm(
      context,
      title: '¿Cerrar sesión?',
      message: 'Primero se sincronizan tus cambios; después se borran los datos de este dispositivo.',
      confirmText: 'Cerrar sesión',
      danger: true,
    );
    if (!confirmed || !context.mounted) return;
    // After a successful sign-out the app shows the login screen on its own.
    await context.read<AppState>().logout(
      confirmUnsynced: () => showConfirm(
        context,
        message: 'Hay cambios sin sincronizar — ¿salir igualmente? Los que no se hayan subido se perderán.',
        confirmText: 'Salir igualmente',
        danger: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.palette;
    return Section(
      title: 'Cuenta',
      children: [
        ListRow(icon: 'globe', iconTint: p.blue, title: 'Servidor', subtitle: app.serverUrl ?? '—'),
        ListRow(
          icon: 'personCircle',
          iconTint: p.grey,
          title: app.deviceName ?? 'Este dispositivo',
          subtitle: 'Este dispositivo · ${syncStatusText(app)}',
          onTap: app.sync,
        ),
        ListRow(
          icon: 'key',
          iconTint: p.indigo,
          title: 'Dispositivos conectados',
          accessory: RowAccessory.chevron,
          onTap: () => showDevicesSheet(context),
        ),
        ListRow(
          icon: 'shield',
          iconTint: p.red,
          title: 'Revocar acceso de Claude',
          danger: true,
          onTap: () => _revokeClaude(context),
        ),
        ListRow(icon: 'signOut', iconTint: p.red, title: 'Cerrar sesión', danger: true, onTap: () => _signOut(context)),
      ],
    );
  }
}
