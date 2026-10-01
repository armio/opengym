import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;

import 'models/models.dart';
import 'sync_protocol.dart';

/// Base of every API failure. [message] is a Spanish, user-presentable text (the server's
/// `{error}` when it sent one).
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No connection, DNS failure, timeout — nothing reached the server (or nothing came back).
class OfflineException extends ApiException {
  const OfflineException([super.message = 'Sin conexión con el servidor.']);
}

/// 401: the device token is unknown or revoked (or, on login, the password is wrong).
class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = 'La sesión ha caducado: vuelve a iniciar sesión.']);
}

/// 409: a precondition failed (proposal no longer pending, a doc changed). [body] may carry
/// the server's current `proposal`.
class ConflictException extends ApiException {
  const ConflictException(super.message, this.body);

  final JsonMap body;
}

/// 429: too many login attempts.
class RateLimitedException extends ApiException {
  const RateLimitedException([super.message = 'Demasiados intentos. Espera unos minutos y vuelve a probar.']);
}

/// 5xx.
class ServerException extends ApiException {
  const ServerException(super.message, this.status);

  final int status;
}

/// Any other non-2xx status (400, 403, 404, 413, 415 …).
class RequestException extends ApiException {
  const RequestException(super.message, this.status);

  final int status;
}

/// Checks and normalises the server address typed at login: `https://…`, or plain `http://`
/// only for local development (localhost, 127.0.0.1, the Android emulator's 10.0.2.2). A
/// missing scheme means https; a pasted connector URL (`…/mcp`) is reduced to the origin.
///
/// Returns `scheme://host[:port]` (lowercase, no trailing slash) or throws a [FormatException]
/// with a Spanish message.
String normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) throw const FormatException('Escribe la dirección de tu servidor.');
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) throw const FormatException('Esa dirección no es válida.');
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  const devHosts = {'localhost', '127.0.0.1', '10.0.2.2', '::1'};
  if (scheme != 'https' && !(scheme == 'http' && devHosts.contains(host))) {
    throw const FormatException('La dirección debe empezar por https:// (http:// solo para localhost).');
  }
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path == '/mcp') path = '';
  final hostPart = host.contains(':') ? '[$host]' : host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '$scheme://$hostPart$port$path';
}

/// Supplies the IANA time zone sent as `X-Timezone`.
typedef TimeZoneProvider = Future<String> Function();

/// The device's IANA zone (via `flutter_timezone`), cached; `UTC` when the platform can't tell.
class DeviceTimeZone {
  DeviceTimeZone._();

  static String? _cached;

  static Future<String> current() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return _cached = info.identifier.isEmpty ? 'UTC' : info.identifier;
    } on MissingPluginException {
      return _cached = 'UTC';
    } catch (_) {
      return _cached = 'UTC';
    }
  }

  /// Forgets the cached zone (call on resume: the owner may have travelled).
  static void refresh() => _cached = null;
}

/// Result of `POST /api/auth/login`.
class LoginResult {
  const LoginResult({required this.token, required this.deviceId});

  final String token;
  final String deviceId;
}

/// A row of `GET /api/devices`.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastSeenAt,
    required this.current,
  });

  factory DeviceInfo.fromJson(Object? json) {
    final m = asMap(json);
    return DeviceInfo(
      id: asString(m['id']) ?? '',
      name: asString(m['name']) ?? '',
      createdAt: asInt(m['createdAt']) ?? 0,
      lastSeenAt: asInt(m['lastSeenAt']),
      current: asBool(m['current']) ?? false,
    );
  }

  final String id;
  final String name;
  final int createdAt;
  final int? lastSeenAt;

  /// The device making the request.
  final bool current;
}

/// Response of `POST /api/proposals/:id/resolve|revert`.
class ProposalWriteResult {
  const ProposalWriteResult({required this.proposal, required this.docs});

  factory ProposalWriteResult.fromJson(Object? json) {
    final m = asMap(json);
    return ProposalWriteResult(
      proposal: Proposal.fromJson(m['proposal']),
      docs: [for (final d in asList(m['docs'])) ServerDoc.fromJson(d)],
    );
  }

  final Proposal proposal;
  final List<ServerDoc> docs;
}

/// Response of `POST /api/import/opengym`.
class ImportResult {
  const ImportResult({required this.workouts, required this.bodyweight, required this.routines});

  factory ImportResult.fromJson(Object? json) {
    final m = asMap(asMap(json)['imported']);
    return ImportResult(
      workouts: asInt(m['workouts']) ?? 0,
      bodyweight: asInt(m['bodyweight']) ?? 0,
      routines: asInt(m['routines']) ?? 0,
    );
  }

  final int workouts;
  final int bodyweight;
  final int routines;
}

/// HTTP client for the Worker's `/api/*` (contract §4): bearer token, `X-Timezone` on every
/// request, JSON in and out, typed [ApiException]s.
class ApiClient implements SyncApi {
  /// [timeout], when given, replaces every per-call timeout (tests).
  ApiClient({required this.baseUrl, this.token, http.Client? httpClient, TimeZoneProvider? timeZone, Duration? timeout})
    : _http = httpClient ?? http.Client(),
      _timeZone = timeZone ?? DeviceTimeZone.current,
      _timeoutOverride = timeout;

  /// Normalised origin, e.g. `https://opengym.example.workers.dev`.
  final String baseUrl;

  /// Device token; null before login.
  String? token;

  final http.Client _http;
  final TimeZoneProvider _timeZone;
  final Duration? _timeoutOverride;

  static const _defaultTimeout = Duration(seconds: 30);

  /// `POST /api/auth/login`. A 401 here means a wrong password.
  Future<LoginResult> login({required String password, required String deviceName}) async {
    final res = await _send(
      'POST',
      '/api/auth/login',
      body: {'password': password, 'deviceName': deviceName},
      auth: false,
    );
    final t = asString(res['token']);
    if (t == null || t.isEmpty) throw const ServerException('Respuesta de login inesperada.', 200);
    return LoginResult(token: t, deviceId: asString(res['deviceId']) ?? '');
  }

  /// `POST /api/auth/logout` — revokes this device's token.
  Future<void> logout() => _send('POST', '/api/auth/logout', body: const {});

  @override
  Future<SyncResponse> pull(int since) async =>
      _syncResponse(await _send('GET', '/api/sync?since=$since', timeout: const Duration(seconds: 60)));

  @override
  Future<SyncResponse> push(JsonMap body) async =>
      _syncResponse(await _send('POST', '/api/sync', body: body, timeout: const Duration(seconds: 60)));

  /// A 2xx sync answer must carry the Worker's counters. Anything else (an HTML login page from an
  /// access proxy, a captive portal, an empty body) is a server error, never a response: read as
  /// `seq 0, epoch 0` it would look like a restored database and discard unsynced doc edits.
  static SyncResponse _syncResponse(Object? body) {
    if (body is! Map || body['seq'] is! int || body['epoch'] is! int) {
      throw const ServerException('Respuesta inesperada del servidor de sincronización.', 200);
    }
    return SyncResponse.fromJson(body);
  }

  /// `POST /api/proposals/:id/resolve` (contract §4.3).
  Future<ProposalWriteResult> resolveProposal(String id, JsonMap body) async => ProposalWriteResult.fromJson(
    await _send('POST', '/api/proposals/${Uri.encodeComponent(id)}/resolve', body: body),
  );

  /// `POST /api/proposals/:id/revert` (contract §4.3).
  Future<ProposalWriteResult> revertProposal(String id, JsonMap body) async =>
      ProposalWriteResult.fromJson(await _send('POST', '/api/proposals/${Uri.encodeComponent(id)}/revert', body: body));

  /// `POST /api/import/opengym` (contract §4.4).
  Future<ImportResult> importBackup(JsonMap state, {String mode = 'replace'}) async => ImportResult.fromJson(
    await _send(
      'POST',
      '/api/import/opengym',
      body: {'state': state, 'mode': mode},
      timeout: const Duration(minutes: 5),
    ),
  );

  /// `POST /api/reset` (contract §4.6).
  Future<void> reset() =>
      _send('POST', '/api/reset', body: const {'confirm': 'RESET'}, timeout: const Duration(minutes: 2));

  /// `GET /api/devices`.
  Future<List<DeviceInfo>> devices() async {
    final res = await _sendRaw('GET', '/api/devices');
    final list = res is List ? res : asList(asMap(res)['devices']);
    return [for (final d in list) DeviceInfo.fromJson(d)];
  }

  /// `POST /api/devices/:id/revoke`.
  Future<void> revokeDevice(String id) =>
      _send('POST', '/api/devices/${Uri.encodeComponent(id)}/revoke', body: const {});

  /// `POST /api/oauth/revoke-all` — revokes every Claude connector grant.
  Future<void> revokeClaudeAccess() => _send('POST', '/api/oauth/revoke-all', body: const {});

  /// `GET /api/health`.
  Future<JsonMap> health() => _send('GET', '/api/health', auth: false);

  void close() => _http.close();

  Future<JsonMap> _send(String method, String path, {Object? body, bool auth = true, Duration? timeout}) async =>
      asMap(await _sendRaw(method, path, body: body, auth: auth, timeout: timeout));

  Future<dynamic> _sendRaw(String method, String path, {Object? body, bool auth = true, Duration? timeout}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Accept'] = 'application/json';
    request.headers['X-Timezone'] = await _timeZone();
    if (auth && token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final limit = _timeoutOverride ?? timeout ?? _defaultTimeout;
    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(limit);
      response = await http.Response.fromStream(streamed).timeout(limit);
    } on TimeoutException {
      throw const OfflineException('El servidor no respondió a tiempo.');
    } on http.ClientException {
      throw const OfflineException();
    } catch (e) {
      // SocketException / HandshakeException (dart:io) and XMLHttpRequest errors (web).
      if (e is ApiException) rethrow;
      throw const OfflineException();
    }
    final decoded = _decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    final serverMessage = decoded is Map ? asString(decoded['error']) : null;
    final status = response.statusCode;
    switch (status) {
      case 401:
        throw serverMessage == null ? const UnauthorizedException() : UnauthorizedException(serverMessage);
      case 409:
        throw ConflictException(serverMessage ?? 'Los datos cambiaron en el servidor.', asMap(decoded));
      case 429:
        throw serverMessage == null ? const RateLimitedException() : RateLimitedException(serverMessage);
    }
    if (status >= 500) throw ServerException(serverMessage ?? 'Error del servidor ($status).', status);
    throw RequestException(serverMessage ?? 'Error de la petición ($status).', status);
  }

  static dynamic _decode(List<int> bytes) {
    if (bytes.isEmpty) return const <String, dynamic>{};
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      return const <String, dynamic>{};
    }
  }
}
