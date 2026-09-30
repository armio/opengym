import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_store.dart';
import 'models/json.dart';

LocalStore createPlatformStore() => FileLocalStore();

/// [LocalStore] backed by files in the app documents directory. Writes go through one queue;
/// `state.json` is written to a temp file and renamed over the old one.
class FileLocalStore implements LocalStore {
  FileLocalStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;
  Future<void> _queue = Future.value();

  Future<File> _file(String name) async => File(p.join((await _directory()).path, name));

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<JsonMap?> _read(String name) => _serial(() async {
    final file = await _file(name);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? deepCopyMap(decoded) : null;
    } on FormatException catch (e) {
      // Keep the unreadable file for inspection instead of silently overwriting it.
      debugPrint('local store: $name is corrupt ($e); moving it aside');
      await file.rename('${file.path}.corrupt');
      return null;
    }
  });

  Future<void> _write(String name, JsonMap value) => _serial(() async {
    final file = await _file(name);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(file.path);
  });

  Future<void> _delete(String name) => _serial(() async {
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  });

  @override
  Future<JsonMap?> readState() => _read('state.json');

  @override
  Future<void> writeState(JsonMap state) => _write('state.json', state);

  @override
  Future<JsonMap?> readActive() => _read('active.json');

  @override
  Future<void> writeActive(JsonMap active) => _write('active.json', active);

  @override
  Future<void> deleteActive() => _delete('active.json');

  @override
  Future<void> clear() async {
    await _delete('state.json');
    await _delete('active.json');
  }
}
