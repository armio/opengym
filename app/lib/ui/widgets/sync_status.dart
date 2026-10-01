import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/sync.dart';
import '../theme.dart';
import 'sheets.dart';

/// The first-sync question (contract §3.3.3) for rows that exist only on this device while the
/// server already has data. True uploads them; false discards them from this device.
Future<bool> confirmUploadLocalOnly(BuildContext context, LocalOnlyData localOnly) {
  final parts = [
    if (localOnly.workouts > 0) '${localOnly.workouts} ${localOnly.workouts == 1 ? 'entreno' : 'entrenos'}',
    if (localOnly.bodyWeights > 0) '${localOnly.bodyWeights} ${localOnly.bodyWeights == 1 ? 'pesaje' : 'pesajes'}',
    if (localOnly.exWeights > 0)
      '${localOnly.exWeights} ${localOnly.exWeights == 1 ? 'peso de trabajo' : 'pesos de trabajo'}',
  ];
  return showConfirm(
    context,
    title: '¿Subir los entrenos de este dispositivo?',
    message:
        'Este dispositivo tiene ${parts.join(', ')} que no están en el servidor. '
        'Si no los subes, se borrarán de este dispositivo.',
    confirmText: 'Subir',
    cancelText: 'Descartar',
    // Discarding deletes rows that exist nowhere else: only an explicit tap may choose it, never
    // a stray tap on the backdrop or a back gesture.
    locked: true,
  );
}

/// Spanish one-line description of the sync state.
String syncStatusText(AppState app) => switch (app.syncStatus) {
  SyncStatus.syncing => 'Sincronizando…',
  SyncStatus.offline =>
    app.hasUnsyncedChanges ? 'Sin conexión — ${app.unsyncedCount} cambios esperan en este dispositivo' : 'Sin conexión',
  SyncStatus.error => app.lastSyncError ?? 'Error al sincronizar',
  SyncStatus.idle => app.hasUnsyncedChanges ? 'Cambios pendientes de sincronizar' : 'Todo sincronizado',
};

/// A small cloud icon reflecting [AppState.syncStatus]; tapping it syncs now and shows the
/// state as a toast. For headers (Inicio, Ajustes).
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.palette;
    final (IconData icon, Color color) = switch (app.syncStatus) {
      SyncStatus.syncing => (Icons.cloud_sync_outlined, p.label3),
      SyncStatus.offline => (Icons.cloud_off_outlined, p.orange),
      SyncStatus.error => (Icons.error_outline_rounded, p.red),
      SyncStatus.idle =>
        app.hasUnsyncedChanges ? (Icons.cloud_upload_outlined, p.label3) : (Icons.cloud_done_outlined, p.label3),
    };
    final text = syncStatusText(app);
    return Semantics(
      button: true,
      label: text,
      child: Tooltip(
        message: text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            showToast(context, text);
            app.sync();
          },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}

/// A slim banner for the shell when the device is offline or sync failed; hidden otherwise.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final visible = app.syncStatus == SyncStatus.offline || app.syncStatus == SyncStatus.error;
    final p = context.palette;
    return AnimatedSwitcher(
      duration: AppMotion.med,
      child: !visible
          ? const SizedBox.shrink()
          : GestureDetector(
              key: const ValueKey('sync-banner'),
              onTap: app.sync,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: (app.syncStatus == SyncStatus.offline ? p.orange : p.red).withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      app.syncStatus == SyncStatus.offline ? Icons.cloud_off_outlined : Icons.error_outline_rounded,
                      size: 15,
                      color: app.syncStatus == SyncStatus.offline ? p.orange : p.red,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        syncStatusText(app),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.label),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
