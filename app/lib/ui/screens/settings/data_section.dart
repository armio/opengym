import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/api_client.dart';
import '../../../data/app_state.dart';
import '../../../data/models/json.dart';
import '../../shell.dart';
import '../../theme.dart';
import '../../widgets/widgets.dart';
import 'backup_files.dart';
import 'reset_dialog.dart';

/// The long-running data tasks; while one runs the others are disabled.
enum _DataTask { importing, resetting }

/// "Datos": export an openGym backup (works offline), import one (replaces every piece of
/// training data on the server, then re-downloads it — contract §4.4) and "Borrar todo"
/// (contract §4.6).
class DataSection extends StatefulWidget {
  const DataSection({super.key, required this.files});

  final BackupFiles files;

  @override
  State<DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<DataSection> {
  _DataTask? _running;

  void _toast(String message) {
    if (mounted) showToast(context, message);
  }

  Future<void> _export() async {
    final app = context.read<AppState>();
    final bytes = encodeBackup(app.exportOpenGymState());
    try {
      final shared = await widget.files.share(backupFileName(app.clock.now()), bytes);
      if (shared) _toast('Copia exportada');
    } on Exception catch (e) {
      debugPrint('export: $e');
      _toast('No se pudo exportar la copia');
    }
  }

  Future<void> _import() async {
    final Uint8List? bytes;
    try {
      bytes = await widget.files.pick();
    } on Exception catch (e) {
      debugPrint('import: $e');
      _toast('No se pudo leer el archivo');
      return;
    }
    if (bytes == null || !mounted) return;

    final JsonMap state;
    try {
      state = decodeBackup(bytes);
    } on BackupFormatException catch (e) {
      _toast('Importación fallida: ${e.message}');
      return;
    }
    final confirmed = await showConfirm(
      context,
      title: '¿Importar copia?',
      message:
          'Esto sustituye todos los datos actuales —en el servidor y en todos tus dispositivos— '
          'por los del archivo de copia.',
      confirmText: 'Importar',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    await _run(_DataTask.importing, () async {
      final result = await context.read<AppState>().importBackup(state);
      _toast(
        'Copia importada: ${_count(result.workouts, 'entreno', 'entrenos')}, '
        '${_count(result.routines, 'rutina', 'rutinas')}',
      );
    }, failure: 'Importación fallida');
  }

  Future<void> _reset() async {
    if (!await showResetConfirm(context) || !mounted) return;
    await _run(_DataTask.resetting, () async {
      await context.read<AppState>().resetAll();
      _toast('Todos los datos borrados');
      if (mounted) context.read<ShellController?>()?.goTo(AppTab.home, popToRoot: true);
    }, failure: 'No se pudo borrar');
  }

  /// Runs an online [task], showing progress on its row; API failures become a toast.
  Future<void> _run(_DataTask kind, Future<void> Function() task, {required String failure}) async {
    setState(() => _running = kind);
    try {
      await task();
    } on ApiException catch (e) {
      _toast('$failure: ${e.message}');
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  static String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final idle = _running == null;
    Widget? progress(_DataTask kind) => _running == kind
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : null;
    return Section(
      title: 'Datos',
      footer: 'La copia es un archivo JSON de openGym: sirve también para la app original.',
      children: [
        ListRow(
          icon: 'download',
          iconTint: p.blue,
          title: 'Exportar copia (JSON)',
          accessory: RowAccessory.chevron,
          onTap: idle ? _export : null,
        ),
        ListRow(
          icon: 'upload',
          iconTint: p.blue,
          title: 'Importar copia de openGym',
          trailing: progress(_DataTask.importing),
          accessory: idle ? RowAccessory.chevron : RowAccessory.none,
          onTap: idle ? _import : null,
        ),
        ListRow(
          icon: 'trash',
          iconTint: p.red,
          title: 'Borrar todo',
          danger: true,
          trailing: progress(_DataTask.resetting),
          onTap: idle ? _reset : null,
        ),
      ],
    );
  }
}
