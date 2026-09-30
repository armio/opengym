import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/dates.dart';
import '../../../data/models/json.dart';

/// Largest backup the server accepts (`POST /api/import/opengym`, contract §4.4).
const maxBackupBytes = 20 * 1024 * 1024;

/// A backup file that cannot be imported; [message] is Spanish and completes
/// "Importación fallida: …".
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// `opengym-backup-YYYY-MM-DD.json` for the local date of [now].
String backupFileName(DateTime now) => 'opengym-backup-${isoDate(now)}.json';

/// The backup document as the original writes it: pretty-printed with two spaces, UTF-8.
Uint8List encodeBackup(JsonMap state) =>
    Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(state)));

/// Parses an openGym backup: a JSON object whose `workouts` and `routines` are lists (the
/// server's own check). Throws [BackupFormatException] otherwise.
JsonMap decodeBackup(Uint8List bytes) {
  if (bytes.length > maxBackupBytes) throw const BackupFormatException('la copia supera los 20 MB');
  final Object? json;
  try {
    final text = utf8.decode(bytes);
    json = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
  } on FormatException {
    throw const BackupFormatException('el archivo no es un JSON válido');
  }
  if (json is! JsonMap || json['workouts'] is! List || json['routines'] is! List) {
    throw const BackupFormatException('no es una copia de openGym');
  }
  return json;
}

/// Moves backup files between the app and the device: picking one to import and handing one
/// to the share sheet. An interface so the Settings screen can be tested without plugins.
abstract interface class BackupFiles {
  /// Lets the owner choose a `.json` file; its bytes, or null when cancelled.
  Future<Uint8List?> pick();

  /// Offers [bytes] as [fileName] through the OS share sheet (a download on the web).
  /// Resolves to false when the owner dismissed the sheet.
  Future<bool> share(String fileName, Uint8List bytes);
}

/// [BackupFiles] on top of `file_picker` and `share_plus`.
class PlatformBackupFiles implements BackupFiles {
  const PlatformBackupFiles();

  @override
  Future<Uint8List?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Importar copia de openGym',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    return file?.readAsBytes();
  }

  @override
  Future<bool> share(String fileName, Uint8List bytes) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/json', name: fileName)],
        fileNameOverrides: [fileName],
        subject: fileName,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}
