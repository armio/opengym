import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opengym/data/api_client.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/clock.dart';
import 'package:opengym/data/local_store.dart';
import 'package:opengym/data/session_store.dart';
import 'package:opengym/ui/screens/settings/settings_screen.dart';

import '../../data/fake_server.dart';
import '../../widgets/test_app.dart';

/// [BackupFiles] that hands out [toPick] and records what was shared.
class FakeBackupFiles implements BackupFiles {
  Uint8List? toPick;
  final shared = <(String, Uint8List)>[];

  @override
  Future<Uint8List?> pick() async => toPick;

  @override
  Future<bool> share(String fileName, Uint8List bytes) async {
    shared.add((fileName, bytes));
    return true;
  }
}

/// A signed-in [AppState] on in-memory storage whose server is a [FakeSyncServer] extended
/// with the account and data endpoints the Settings screen calls.
class SettingsHarness {
  SettingsHarness() {
    app = AppState(
      library: loadTestLibrary(),
      store: MemoryLocalStore(),
      sessions: MemorySessionStore(),
      session: const SessionInfo(
        serverUrl: 'https://gym.example.com',
        deviceName: 'Pixel',
        deviceId: 'd1',
        token: 'tok',
      ),
      clock: FakeClock(DateTime(2026, 9, 30, 18)),
      apiFactory: (url, token) => ApiClient(
        baseUrl: url,
        token: token,
        timeZone: () async => 'Europe/Madrid',
        httpClient: server.httpClient(log: requests, handlers: _handlers),
      ),
    );
  }

  final server = FakeSyncServer();
  final files = FakeBackupFiles();
  final requests = <http.Request>[];
  late final AppState app;

  /// The body of the last `POST /api/import/opengym`.
  Map<String, dynamic>? importedBody;

  /// When true, the import and reset endpoints are unreachable.
  bool offline = false;

  /// Routes (`'POST /api/reset'`) of every request made, in order.
  List<String> get routes => [for (final r in requests) '${r.method} ${r.url.path}'];

  late final Map<String, Future<http.Response> Function(http.Request)> _handlers = {
    'GET /api/devices': (_) async => _json([
      {'id': 'd1', 'name': 'Pixel', 'createdAt': 1790000000000, 'lastSeenAt': 1790500000000, 'current': true},
      {'id': 'd2', 'name': 'iPad', 'createdAt': 1790000000000, 'lastSeenAt': null, 'current': false},
    ]),
    'POST /api/devices/d2/revoke': (_) async => _json({'ok': true}),
    'POST /api/oauth/revoke-all': (_) async => _json({'ok': true, 'revoked': 1}),
    'POST /api/import/opengym': (request) async {
      if (offline) throw http.ClientException('offline');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      importedBody = body;
      final state = body['state'] as Map<String, dynamic>;
      server.putDoc('plan', {'routines': state['routines'], 'week': state['week'] ?? {}, 'customEx': []});
      for (final w in state['workouts'] as List) {
        server.putWorkout(w as Map<String, dynamic>);
      }
      return _json({
        'imported': {
          'workouts': (state['workouts'] as List).length,
          'bodyweight': 0,
          'routines': (state['routines'] as List).length,
        },
      });
    },
    'POST /api/reset': (_) async {
      if (offline) throw http.ClientException('offline');
      for (final row in server.workouts.values.toList()) {
        server.putWorkout({...row, 'data': null}, deleted: true, updatedAt: server.serverTime + 1);
      }
      server.putDoc('plan', {'routines': [], 'week': {}, 'customEx': []});
      return _json({'ok': true});
    },
  };

  static http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}

/// Captures `Clipboard.setData` calls; returns a getter for the last copied text.
String? Function() captureClipboard(WidgetTester tester) {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return () => copied;
}

/// Pumps the Settings screen for [harness] on a tall viewport ([width] 360 = a phone).
Future<void> pumpSettings(WidgetTester tester, SettingsHarness harness, {double width = 900}) async {
  tester.view
    ..physicalSize = Size(width, 5000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpWithApp(tester, harness.app, SettingsScreen(backupFiles: harness.files));
}
