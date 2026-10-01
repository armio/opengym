import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where this device talks to and as whom. The token is secret; the rest is not.
class SessionInfo {
  const SessionInfo({this.serverUrl, this.deviceName, this.deviceId, this.token});

  /// Normalised server origin (kept after sign-out to prefill the login form).
  final String? serverUrl;
  final String? deviceName;
  final String? deviceId;

  /// Bearer token; null when signed out.
  final String? token;

  bool get isSignedIn => serverUrl != null && token != null && token!.isNotEmpty;

  SessionInfo withoutToken() => SessionInfo(serverUrl: serverUrl, deviceName: deviceName, deviceId: deviceId);
}

/// Persists [SessionInfo]: server URL / device name in `shared_preferences`, the token in
/// `flutter_secure_storage` (contract §6).
abstract interface class SessionStore {
  factory SessionStore.platform() = _PlatformSessionStore;

  Future<SessionInfo> load();
  Future<void> save(SessionInfo session);

  /// Forgets the token, keeping the server URL and device name.
  Future<void> clearToken();
}

class _PlatformSessionStore implements SessionStore {
  static const _serverKey = 'opengym.serverUrl';
  static const _deviceNameKey = 'opengym.deviceName';
  static const _deviceIdKey = 'opengym.deviceId';
  static const _tokenKey = 'opengym.token';

  final _secure = const FlutterSecureStorage();

  @override
  Future<SessionInfo> load() async {
    final prefs = await SharedPreferences.getInstance();
    String? token;
    try {
      token = await _secure.read(key: _tokenKey);
    } catch (e) {
      // An unreadable keystore entry means signing in again, not crashing.
      debugPrint('session: cannot read token ($e)');
    }
    return SessionInfo(
      serverUrl: prefs.getString(_serverKey),
      deviceName: prefs.getString(_deviceNameKey),
      deviceId: prefs.getString(_deviceIdKey),
      token: token,
    );
  }

  @override
  Future<void> save(SessionInfo session) async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> put(String key, String? value) async =>
        value == null ? await prefs.remove(key) : await prefs.setString(key, value);
    await put(_serverKey, session.serverUrl);
    await put(_deviceNameKey, session.deviceName);
    await put(_deviceIdKey, session.deviceId);
    if (session.token == null) {
      await _secure.delete(key: _tokenKey);
    } else {
      await _secure.write(key: _tokenKey, value: session.token);
    }
  }

  @override
  Future<void> clearToken() async {
    try {
      await _secure.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('session: cannot delete token ($e)');
    }
  }
}

/// In-memory [SessionStore] for tests.
class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session = const SessionInfo()]);

  SessionInfo session;

  @override
  Future<SessionInfo> load() async => session;

  @override
  Future<void> save(SessionInfo value) async => session = value;

  @override
  Future<void> clearToken() async => session = session.withoutToken();
}
