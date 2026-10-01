import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opengym/data/api_client.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/clock.dart';
import 'package:opengym/data/health/health_bridge.dart';
import 'package:opengym/data/health/health_prefs.dart';
import 'package:opengym/data/health/health_sync.dart';
import 'package:opengym/data/local_store.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/data/session_store.dart';

import '../fake_server.dart';
import 'fake_health_bridge.dart';

void main() {
  late FakeSyncServer server;
  late FakeClock clock;
  late AppState app;
  late FakeHealthBridge bridge;
  late MemoryHealthPrefsStore prefs;
  late HealthSync health;
  late List<JsonMap> uploads;
  late int clears;
  late bool offline;

  final now = DateTime(2026, 9, 30, 18);

  setUp(() {
    server = FakeSyncServer();
    clock = FakeClock(now);
    uploads = [];
    clears = 0;
    offline = false;
    final handlers = <String, Future<http.Response> Function(http.Request)>{
      'POST /api/recovery': (request) async {
        if (offline) throw http.ClientException('offline');
        uploads.add(jsonDecode(request.body) as JsonMap);
        return http.Response('{"ok":true,"stored":0,"deleted":0}', 200, headers: {'content-type': 'application/json'});
      },
      'POST /api/recovery/clear': (request) async {
        if (offline) throw http.ClientException('offline');
        clears++;
        return http.Response('{"ok":true,"deleted":0}', 200, headers: {'content-type': 'application/json'});
      },
    };
    app = AppState(
      library: loadTestLibrary(),
      store: MemoryLocalStore(),
      sessions: MemorySessionStore(),
      session: const SessionInfo(
        serverUrl: 'https://gym.example.com',
        deviceName: 'iPhone',
        deviceId: 'd1',
        token: 'tok',
      ),
      clock: clock,
      apiFactory: (url, token) => ApiClient(
        baseUrl: url,
        token: token,
        timeZone: () async => 'Europe/Madrid',
        httpClient: server.httpClient(handlers: handlers),
      ),
    );
    bridge = FakeHealthBridge();
    prefs = MemoryHealthPrefsStore();
    health = HealthSync(
      app: app,
      bridge: bridge,
      store: prefs,
      clock: clock,
      observeLifecycle: false,
      exportDelay: const Duration(milliseconds: 10),
    );
  });

  tearDown(() {
    health.dispose();
    app.dispose();
  });

  Workout workout(String id, DateTime start, {int minutes = 60, num? bw}) => Workout.fromJson({
    ...workoutJson(
      id,
      d: '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
    ),
    'start': start.millisecondsSinceEpoch,
    'end': start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
    'bw': bw,
  });

  HealthReading scale(String uuid, DateTime at, double kg) => HealthReading(uuid: uuid, start: at, end: at, value: kg);

  Future<void> connect() async {
    await health.start();
    await health.connect();
  }

  group('without Apple Health', () {
    test('start does nothing and the section stays hidden', () async {
      bridge.supported = false;
      await health.start();
      expect(health.isLoaded, isFalse);
      await health.sync(readHealth: true);
      expect(bridge.calls, isEmpty);
      expect(prefs.saved, isNull);
    });
  });

  group('connect', () {
    test('asks for permission once, then saves recent workouts and backfills 90 days of recovery', () async {
      app.saveWorkout(workout('recent', now.subtract(const Duration(days: 3)), bw: 80));
      app.saveWorkout(workout('old', now.subtract(const Duration(days: 20))));
      app.saveWorkout(workout('imported', now.subtract(const Duration(days: 2)), minutes: 0));
      bridge.restingHeartRate = [scale('r', DateTime(2026, 9, 30, 7), 55)];

      await health.start();
      expect(bridge.calls, isEmpty, reason: 'nothing runs before connecting');
      await health.connect();

      expect(bridge.authorizations, 1);
      expect(health.isConnected, isTrue);
      expect(bridge.workouts.values.single.kcal, 200);
      expect(bridge.workouts.values.single.start, now.subtract(const Duration(days: 3)));
      final days = (uploads.single['days'] as List).cast<JsonMap>();
      expect(days, hasLength(90));
      expect(days.first, {'d': '2026-07-03'});
      expect(days.last, {'d': '2026-09-30', 'rhr': 55.0});
      expect(health.lastError, isNull);
      expect(health.lastSyncAt, now);
      expect(HealthPrefs.fromJson(prefs.saved).workouts.keys, ['recent']);
    });

    test('reports a refused permission sheet and stays disconnected', () async {
      await health.start();
      bridge.failure = const HealthUnavailableException('No se pudo acceder a Apple Health.');
      await expectLater(health.connect(), throwsA(isA<HealthUnavailableException>()));
      expect(health.isConnected, isFalse);
    });
  });

  group('workouts → Health', () {
    test('saves each workout once, rewrites a changed one and removes a deleted one', () async {
      await connect();
      final w = workout('w1', now.subtract(const Duration(hours: 2)));
      app.saveWorkout(w);
      await health.sync();
      await health.sync();
      expect(bridge.workouts, hasLength(1));
      final firstUuid = bridge.workouts.keys.single;

      app.saveWorkout(w.copy()..end = w.end + 15 * 60000);
      await health.sync();
      expect(bridge.workouts.keys.single, isNot(firstUuid));
      expect(bridge.workouts.values.single.end, DateTime.fromMillisecondsSinceEpoch(w.end + 15 * 60000));

      app.deleteWorkout('w1');
      await health.sync();
      expect(bridge.workouts, isEmpty);
      expect(HealthPrefs.fromJson(prefs.saved).workouts, isEmpty);
    });

    test('a workout that is merely missing (signed out) is not removed from Health', () async {
      await connect();
      app.saveWorkout(workout('w1', now.subtract(const Duration(hours: 2))));
      await health.sync();
      await app.logout(confirmUnsynced: () async => true);
      await health.sync();
      expect(bridge.workouts, hasLength(1));
    });

    test('runs by itself shortly after a workout is saved', () async {
      await connect();
      app.saveWorkout(workout('w1', now.subtract(const Duration(hours: 1))));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bridge.workouts, hasLength(1));
    });

    test('estimates calories from the last weigh-in, converting pounds', () async {
      app.updateSettings((s) => s.unit = 'lb');
      app.setBodyWeight(176.4, date: '2026-09-01', t: DateTime(2026, 9, 1, 8).millisecondsSinceEpoch);
      app.saveWorkout(workout('w1', now.subtract(const Duration(hours: 3))));
      await connect();
      expect(bridge.workouts.values.single.kcal, 200);
    });

    test('can be switched off', () async {
      await connect();
      await health.setWriteWorkouts(false);
      app.saveWorkout(workout('w1', now.subtract(const Duration(hours: 2))));
      await health.sync(readHealth: true);
      expect(bridge.workouts, isEmpty);
    });
  });

  group('body weight', () {
    test('imports the latest scale reading of each day unless openGym has a newer one', () async {
      app.setBodyWeight(81.0, date: '2026-09-28', t: DateTime(2026, 9, 28, 7).millisecondsSinceEpoch);
      app.setBodyWeight(80.0, date: '2026-09-29', t: DateTime(2026, 9, 29, 20).millisecondsSinceEpoch);
      bridge.weights.addAll([
        scale('s1', DateTime(2026, 9, 28, 7, 30), 80.62), // newer than openGym's → replaces it
        scale('s2', DateTime(2026, 9, 29, 7), 79.5), // older than openGym's → ignored
        scale('s3', DateTime(2026, 9, 30, 6), 79.9),
        scale('s4', DateTime(2026, 9, 30, 7), 79.7), // the day's latest wins
      ]);
      await connect();
      expect({for (final b in app.bodyWeights) b.d: b.w}, {'2026-09-28': 80.6, '2026-09-29': 80.0, '2026-09-30': 79.7});
      expect(app.bodyWeights.last.t, DateTime(2026, 9, 30, 7).millisecondsSinceEpoch);
    });

    test('never writes an imported reading back, nor re-imports its own', () async {
      bridge.weights.add(scale('s1', DateTime(2026, 9, 30, 7), 79.7));
      await connect();
      await health.sync(readHealth: true);
      expect(bridge.weights.map((w) => w.uuid), ['s1']);

      app.setBodyWeight(79.2, date: '2026-09-30');
      await health.sync(readHealth: true);
      expect(bridge.weights.map((w) => w.uuid), ['s1', 'w1']);
      expect(app.bodyWeights.single.w, 79.2);
    });

    test('saves openGym weigh-ins in Health, replacing and removing its own copy as they change', () async {
      await connect();
      app.setBodyWeight(80.0, date: '2026-09-30');
      await health.sync();
      expect(bridge.weights.single.value, 80.0);

      clock.advance(const Duration(minutes: 5));
      app.setBodyWeight(79.8, date: '2026-09-30');
      await health.sync();
      expect(bridge.weights.single.value, closeTo(79.8, 1e-9));

      app.deleteBodyWeight('2026-09-30');
      await health.sync(readHealth: true);
      expect(bridge.weights, isEmpty);
      expect(app.bodyWeights, isEmpty);
    });

    test('does not bring back a weigh-in deleted after the reading', () async {
      bridge.weights.add(scale('s1', DateTime(2026, 9, 30, 7), 79.7));
      await connect();
      app.deleteBodyWeight('2026-09-30');
      await health.setSyncWeight(true);
      await health.sync(readHealth: true);
      expect(app.bodyWeights, isEmpty);
    });

    test('converts to pounds', () async {
      app.updateSettings((s) => s.unit = 'lb');
      bridge.weights.add(scale('s1', DateTime(2026, 9, 30, 7), 80));
      await connect();
      expect(app.bodyWeights.single.w, 176.4);
    });
  });

  group('recovery → server', () {
    test('uploads at most hourly unless forced, re-sending the last two weeks', () async {
      await connect();
      expect(uploads, hasLength(1));
      await health.sync(readHealth: true);
      expect(uploads, hasLength(1));

      clock.advance(const Duration(hours: 2));
      await health.sync(readHealth: true);
      expect(uploads, hasLength(2));
      expect((uploads.last['days'] as List).first, {'d': '2026-09-17'});
      await health.sync(readHealth: true, force: true);
      expect(uploads, hasLength(3));
    });

    test('turning sharing off deletes the server copy and stops uploading', () async {
      await connect();
      await health.setShareRecovery(false);
      expect(clears, 1);
      clock.advance(const Duration(hours: 2));
      await health.sync(readHealth: true, force: true);
      expect(uploads, hasLength(1));

      await health.setShareRecovery(true);
      expect(uploads, hasLength(2));
      expect(uploads.last['days'], hasLength(90), reason: 'turning it back on backfills again');
    });

    test('sharing stays on when the server copy cannot be deleted', () async {
      await connect();
      offline = true;
      await expectLater(health.setShareRecovery(false), throwsA(isA<OfflineException>()));
      expect(health.shareRecovery, isTrue);
    });

    test('an offline upload is reported and retried on the next run', () async {
      offline = true;
      await connect();
      expect(health.lastError, 'Sin conexión con el servidor.');
      offline = false;
      await health.sync(readHealth: true);
      expect(uploads, hasLength(1));
      expect(health.lastError, isNull);
    });
  });

  group('disconnect', () {
    test('deletes the server recovery days and stops every step', () async {
      await connect();
      await health.disconnect();
      expect(clears, 1);
      expect(health.isConnected, isFalse);
      bridge.calls.clear();
      app.saveWorkout(workout('w1', now.subtract(const Duration(hours: 1))));
      await health.sync(readHealth: true, force: true);
      expect(bridge.calls, isEmpty);
    });
  });

  test('a failing Health call is reported without stopping the other steps', () async {
    await connect();
    app.saveWorkout(workout('w1', now.subtract(const Duration(hours: 1))));
    bridge.failure = const HealthUnavailableException('No se pudo acceder a Apple Health.');
    clock.advance(const Duration(hours: 2));
    await health.sync(readHealth: true);
    expect(health.lastError, 'No se pudo acceder a Apple Health.');
    bridge.failure = null;
    await health.sync(readHealth: true);
    expect(health.lastError, isNull);
    expect(bridge.workouts, hasLength(1));
  });

  test('settings and bookkeeping survive a restart', () async {
    await connect();
    await health.setSyncWeight(false);
    final again = HealthSync(app: app, bridge: bridge, store: prefs, clock: clock, observeLifecycle: false);
    addTearDown(again.dispose);
    await again.start();
    expect(again.isConnected, isTrue);
    expect(again.syncWeight, isFalse);
    expect(again.lastSyncAt, now);
  });
}
