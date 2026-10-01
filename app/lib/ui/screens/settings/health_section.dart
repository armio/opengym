import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/api_client.dart';
import '../../../data/health/health_bridge.dart';
import '../../../data/health/health_sync.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';

/// "Apple Health" (contract §8): connect, the three sync switches, the last run and disconnect.
/// Hidden on devices without Apple Health.
class HealthSection extends StatelessWidget {
  const HealthSection({super.key});

  @override
  Widget build(BuildContext context) {
    final health = context.watch<HealthSync?>();
    if (health == null || !health.isSupported || !health.isLoaded) return const SizedBox.shrink();
    final p = context.palette;
    if (!health.isConnected) {
      return Section(
        title: 'Apple Health',
        footer:
            'Guarda tus entrenos en Salud, sincroniza tu peso con tu báscula y comparte con Claude tu '
            'frecuencia cardiaca en reposo, variabilidad cardiaca y sueño para que tenga en cuenta tu recuperación.',
        children: [
          ListRow(
            icon: 'heart',
            iconTint: p.pink,
            title: 'Conectar con Apple Health',
            accessory: RowAccessory.chevron,
            onTap: () => _run(context, health.connect),
          ),
        ],
      );
    }
    final error = health.lastError;
    return Section(
      title: 'Apple Health',
      footer: [
        if (error != null) 'Último error: $error',
        'Se sincroniza al abrir la app. Si falta algún dato, revisa los permisos en Ajustes del iPhone → '
            'Salud → Acceso a datos y dispositivos → openGym.',
      ].join('\n'),
      children: [
        SwitchRow(
          icon: 'figureStrength',
          iconTint: p.orange,
          title: 'Guardar entrenos en Salud',
          subtitle: 'Desactívalo si ya los registras con el Apple Watch.',
          value: health.writeWorkouts,
          onChanged: (v) => _run(context, () => health.setWriteWorkouts(v)),
        ),
        SwitchRow(
          icon: 'scale',
          iconTint: p.teal,
          title: 'Sincronizar peso corporal',
          subtitle: 'Tu báscula en openGym y tus pesajes en Salud.',
          value: health.syncWeight,
          onChanged: (v) => _run(context, () => health.setSyncWeight(v)),
        ),
        SwitchRow(
          icon: 'moon',
          iconTint: p.purple,
          title: 'Compartir recuperación con Claude',
          subtitle: 'FC en reposo, variabilidad cardiaca y sueño, guardados en tu servidor.',
          value: health.shareRecovery,
          onChanged: (v) => _run(context, () => health.setShareRecovery(v)),
        ),
        ListRow(
          icon: 'reset',
          iconTint: p.green,
          title: health.isSyncing ? 'Sincronizando…' : 'Sincronizar ahora',
          value: _lastRun(health.lastSyncAt, health.clock.now()),
          onTap: health.isSyncing ? null : () => _run(context, () => health.sync(readHealth: true, force: true)),
        ),
        ListRow(title: 'Desconectar Apple Health', danger: true, onTap: () => _disconnect(context, health)),
      ],
    );
  }

  static String? _lastRun(DateTime? at, DateTime now) {
    if (at == null) return null;
    final minutes = now.difference(at).inMinutes;
    if (minutes < 1) return 'Ahora';
    if (minutes < 60) return 'Hace $minutes min';
    if (minutes < 24 * 60) return 'Hace ${minutes ~/ 60} h';
    return DateFormat('d MMM', 'es').format(at);
  }

  static Future<void> _disconnect(BuildContext context, HealthSync health) async {
    final ok = await showConfirm(
      context,
      title: 'Desconectar Apple Health',
      message: health.shareRecovery
          ? 'Dejarás de sincronizar y se borrarán de tu servidor los datos de recuperación. Lo que ya está '
                'guardado en Salud se queda allí.'
          : 'Dejarás de sincronizar. Lo que ya está guardado en Salud se queda allí.',
      confirmText: 'Desconectar',
      danger: true,
    );
    if (ok && context.mounted) await _run(context, health.disconnect);
  }

  /// Runs [action], toasting the Spanish message of a failure.
  static Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on HealthUnavailableException catch (e) {
      if (context.mounted) showToast(context, e.message);
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }
}
