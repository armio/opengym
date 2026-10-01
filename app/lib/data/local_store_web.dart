import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';
import 'models/json.dart';

LocalStore createPlatformStore() => PrefsLocalStore();

/// [LocalStore] for the web build: the two "files" live in `localStorage` via
/// `shared_preferences` (a single write is atomic there).
class PrefsLocalStore implements LocalStore {
  static const _stateKey = 'opengym.state.json';
  static const _activeKey = 'opengym.active.json';

  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<JsonMap?> _read(String key) => _serial(() async {
    final text = (await SharedPreferences.getInstance()).getString(key);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? deepCopyMap(decoded) : null;
    } on FormatException {
      return null;
    }
  });

  Future<void> _write(String key, JsonMap value) =>
      _serial(() async => (await SharedPreferences.getInstance()).setString(key, jsonEncode(value)));

  Future<void> _delete(String key) => _serial(() async => (await SharedPreferences.getInstance()).remove(key));

  @override
  Future<JsonMap?> readState() => _read(_stateKey);

  @override
  Future<void> writeState(JsonMap state) => _write(_stateKey, state);

  @override
  Future<JsonMap?> readActive() => _read(_activeKey);

  @override
  Future<void> writeActive(JsonMap active) => _write(_activeKey, active);

  @override
  Future<void> deleteActive() => _delete(_activeKey);

  @override
  Future<void> clear() async {
    await _delete(_stateKey);
    await _delete(_activeKey);
  }
}
