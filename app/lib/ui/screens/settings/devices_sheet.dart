import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/api_client.dart';
import '../../../data/app_state.dart';
import '../../../data/dates.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';

/// "Dispositivos conectados": every device signed in to the server, with "Revocar" for the
/// others (this one signs out with "Cerrar sesión"). Needs a connection.
Future<void> showDevicesSheet(BuildContext context) =>
    showAppSheet<void>(context, title: 'Dispositivos conectados', builder: (_) => const _DevicesList());

/// "Añadido el 12 sept · activo el 30 sept".
String describeDevice(DeviceInfo device) {
  String day(int ms) => formatDate(isoDate(DateTime.fromMillisecondsSinceEpoch(ms)));
  final lastSeen = device.lastSeenAt;
  return ['Añadido el ${day(device.createdAt)}', if (lastSeen != null) 'activo el ${day(lastSeen)}'].join(' · ');
}

class _DevicesList extends StatefulWidget {
  const _DevicesList();

  @override
  State<_DevicesList> createState() => _DevicesListState();
}

class _DevicesListState extends State<_DevicesList> {
  late Future<List<DeviceInfo>> _devices = _load();

  Future<List<DeviceInfo>> _load() => context.read<AppState>().listDevices();

  void _reload() {
    // A block body: an arrow would hand the Future back to setState.
    setState(() {
      _devices = _load();
    });
  }

  Future<void> _revoke(DeviceInfo device) async {
    final confirmed = await showConfirm(
      context,
      title: '¿Revocar «${device.name}»?',
      message: 'Ese dispositivo tendrá que volver a iniciar sesión con la contraseña del servidor.',
      confirmText: 'Revocar',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().revokeDevice(device.id);
      if (!mounted) return;
      showToast(context, 'Dispositivo revocado');
      _reload();
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'No se pudo revocar: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FutureBuilder<List<DeviceInfo>>(
      future: _devices,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final error = snapshot.error;
        if (error != null) {
          return EmptyState(
            icon: 'info',
            message: error is ApiException ? error.message : 'No se pudo cargar la lista de dispositivos.',
            action: AppButton('Reintentar', size: ButtonSize.sm, onPressed: _reload),
          );
        }
        final devices = snapshot.data ?? const <DeviceInfo>[];
        return Section(
          footer: 'Revocar un dispositivo cierra su sesión al momento. Para salir de este, usa «Cerrar sesión».',
          children: [
            for (final d in devices)
              ListRow(
                icon: 'key',
                iconTint: d.current ? p.acc : p.indigo,
                title: d.name,
                subtitle: describeDevice(d),
                trailing: d.current
                    ? const Tag('Este dispositivo', accent: true, capitalize: false)
                    : AppButton(
                        'Revocar',
                        size: ButtonSize.xs,
                        variant: ButtonVariant.danger,
                        onPressed: () => _revoke(d),
                      ),
              ),
          ],
        );
      },
    );
  }
}
