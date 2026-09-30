import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/api_client.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/clock.dart';
import 'package:opengym/data/local_store.dart';
import 'package:opengym/data/session_store.dart';
import 'package:opengym/ui/theme.dart';
import 'package:provider/provider.dart';

import '../data/fake_server.dart';

/// An [AppState] on in-memory storage talking to [server] (a fresh fake by default).
AppState testAppState({bool signedIn = true, FakeSyncServer? server, Clock? clock}) {
  final fake = server ?? FakeSyncServer();
  return AppState(
    library: loadTestLibrary(),
    store: MemoryLocalStore(),
    sessions: MemorySessionStore(),
    session: signedIn
        ? const SessionInfo(serverUrl: 'https://gym.example.com', deviceName: 'Test', deviceId: 'd1', token: 'tok')
        : const SessionInfo(),
    clock: clock ?? FakeClock(DateTime(2026, 9, 30, 18)),
    apiFactory: (url, token) =>
        ApiClient(baseUrl: url, token: token, timeZone: () async => 'Europe/Madrid', httpClient: fake.httpClient()),
  );
}

/// Pumps [child] inside a themed MaterialApp with [app] provided.
Future<void> pumpWithApp(WidgetTester tester, AppState app, Widget child) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: child,
      ),
    ),
  );
}

/// Lets debounced persist/sync timers and toasts run out, then disposes [app] so no timer is
/// left pending when the test ends.
Future<void> settleAndDispose(WidgetTester tester, AppState app) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox());
  app.dispose();
}
