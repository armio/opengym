import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opengym/data/api_client.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/clock.dart';
import 'package:opengym/data/local_data.dart';
import 'package:opengym/data/local_store.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/data/session_store.dart';
import 'package:opengym/data/sync.dart';
import 'package:opengym/data/sync_protocol.dart';

import 'fake_server.dart';

void main() {
  late FakeSyncServer server;
  late MemoryLocalStore store;
  late MemorySessionStore sessions;
  late FakeClock clock;
  late AppState app;
  Map<String, Future<http.Response> Function(http.Request)> handlers = {};

  ApiClient api(String url, String? token) => ApiClient(
    baseUrl: url,
    token: token,
    timeZone: () async => 'Europe/Madrid',
    httpClient: server.httpClient(handlers: handlers),
  );

  AppState build({bool signedIn = true, LocalData? data, ActiveWorkout? active}) => AppState(
    library: loadTestLibrary(),
    store: store,
    sessions: sessions,
    data: data,
    active: active,
    session: signedIn
        ? const SessionInfo(serverUrl: 'https://gym.example.com', deviceName: 'Test', deviceId: 'd1', token: 'tok')
        : const SessionInfo(),
    clock: clock,
    apiFactory: api,
  );

  setUp(() {
    server = FakeSyncServer();
    store = MemoryLocalStore();
    sessions = MemorySessionStore();
    clock = FakeClock(DateTime(2026, 9, 30, 18));
    handlers = {};
    app = build();
  });

  tearDown(() => app.dispose());

  LocalData dataOf(AppState a) => LocalData.fromJson(jsonDecode(jsonEncode(store.state)));

  group('multi-doc mutations stamp one updatedAt', () {
    test('deleteRoutine clears the routine, its weekdays and its reschedules', () async {
      app.edit((d) {
        d.plan.routines.addAll([Routine(id: 'r1', name: 'A'), Routine(id: 'r2', name: 'B')]);
        d.plan.week.addAll({'1': 'r1', '3': 'r2', '5': 'r1'});
        d.schedule.dayPlan.addAll({'2026-10-01': 'r1', '2026-10-02': 'rest', '2026-10-03': 'r2'});
      });
      clock.advance(const Duration(minutes: 5));

      app.deleteRoutine('r1');
      await app.flush();

      expect(app.plan.routines.map((r) => r.id), ['r2']);
      expect(app.plan.week, {'3': 'r2'});
      expect(app.schedule.dayPlan, {'2026-10-02': 'rest', '2026-10-03': 'r2'});
      final data = dataOf(app);
      expect(data.docs[DocKey.plan]!.updatedAt, clock.nowMs());
      expect(data.docs[DocKey.schedule]!.updatedAt, data.docs[DocKey.plan]!.updatedAt);
      expect(data.dirtyDocs, containsAll([DocKey.plan, DocKey.schedule]));
    });

    test('deleteCustomExercise touches plan, the working weight and every referencing workout', () async {
      app.edit((d) {
        d.plan.customEx.add(CustomExercise(id: 'cN', n: 'Nordic curl', bp: 'upper legs'));
        d.plan.routines.add(
          Routine(
            id: 'r1',
            name: 'A',
            ex: [
              RoutineExercise(id: '0025', sg: 'g'),
              RoutineExercise(id: 'cN', sg: 'g'),
              RoutineExercise(id: '0043'),
            ],
          ),
        );
        d.putWorkout(Workout.fromJson(workoutJson('w1')..['entries'][0]['id'] = 'cN'));
        d.putWorkout(Workout.fromJson(workoutJson('w2')));
        d.putExWeight('cN', ExWeight(w: 40, d: '2026-09-28'));
      });
      clock.advance(const Duration(minutes: 1));

      expect(app.deleteCustomExercise('cN'), isTrue);
      await app.flush();

      expect(app.plan.customEx, isEmpty);
      expect(app.plan.routines.single.ex.map((e) => e.id), ['0025', '0043']);
      expect(app.plan.routines.single.ex.first.sg, isNull, reason: 'orphaned superset tag cleaned up');
      expect(app.workoutById('w1')!.entries.single.n, 'Nordic curl');
      expect(app.exWeights.containsKey('cN'), isFalse);
      final data = dataOf(app);
      final stamp = data.docs[DocKey.plan]!.updatedAt;
      expect(stamp, clock.nowMs());
      expect(data.workouts['w1']!.updatedAt, stamp);
      expect(data.exWeights['cN']!.updatedAt, stamp);
      expect(data.exWeights['cN']!.deleted, isTrue, reason: 'kept as a tombstone until pushed');
      expect(data.workouts['w2']!.updatedAt, lessThan(stamp), reason: 'unrelated workout untouched');
    });

    test('deleteCustomExercise is refused while the active workout uses it', () async {
      app.updatePlan((p) => p.customEx.add(CustomExercise(id: 'cN', n: 'Nordic', bp: 'upper legs')));
      await app.startActive(
        ActiveWorkout(
          id: 'a1',
          d: '2026-09-30',
          start: 1,
          entries: [ActiveEntry(id: 'cN')],
        ),
      );
      expect(app.deleteCustomExercise('cN'), isFalse);
      expect(app.plan.customEx, hasLength(1));
    });
  });

  test('an edit that throws commits nothing', () {
    expect(
      () => app.edit((d) {
        d.plan.week['1'] = 'r1';
        throw StateError('missing target');
      }),
      throwsStateError,
    );
    expect(app.plan.week, isEmpty);
    expect(app.hasUnsyncedChanges, isFalse);
  });

  test('updatedAt = max(now + clockOffset, previous + 1)', () async {
    final data = LocalData()
      ..clockOffset = 5000
      ..hasClockOffset = true;
    data.docs[DocKey.settings]!.updatedAt = clock.nowMs() + 999999; // stamped by a fast clock earlier
    app.dispose();
    app = build(data: data);

    app.updateSettings((s) => s.restSec = 120);
    app.updatePlan((p) => p.week['1'] = 'r1');
    await app.flush();

    final stored = dataOf(app);
    expect(stored.docs[DocKey.settings]!.updatedAt, clock.nowMs() + 999999 + 1);
    expect(stored.docs[DocKey.plan]!.updatedAt, clock.nowMs() + 5000);
  });

  test('an edit that changes nothing marks nothing dirty', () {
    app.updateSettings((s) => s.unit = 'kg');
    expect(app.hasUnsyncedChanges, isFalse);
  });

  test('workouts are kept sorted by (d, start) and weigh-ins by date', () {
    app.saveWorkout(Workout.fromJson(workoutJson('b', d: '2026-09-28', start: 2)));
    app.saveWorkout(Workout.fromJson(workoutJson('c', d: '2026-09-29', start: 1)));
    app.saveWorkout(Workout.fromJson(workoutJson('a', d: '2026-09-28', start: 1)));
    expect(app.workouts.map((w) => w.id), ['a', 'b', 'c']);

    app.setBodyWeight(79, date: '2026-09-30');
    app.setBodyWeight(80, date: '2026-09-01');
    app.setBodyWeight(78.5, date: '2026-09-30'); // same date: replaced
    expect(app.bodyWeights.map((b) => '${b.d}=${b.w}'), ['2026-09-01=80', '2026-09-30=78.5']);
    expect(app.lastBodyWeight!.w, 78.5);

    app.deleteWorkout('b');
    expect(app.workouts.map((w) => w.id), ['a', 'c']);
  });

  test('updateAthlete stamps savedAt and updatedBy', () {
    app.updateAthlete((a) => a.goal = 'strength');
    expect(app.athlete.savedAt, clock.nowMs());
    expect(app.athlete.updatedBy, 'app');
  });

  group('active workout persistence ordering', () {
    ActiveWorkout active() => ActiveWorkout(id: 'a1', d: '2026-09-30', start: clock.nowMs(), name: 'Push');

    test('start writes state.json before active.json', () async {
      app.setBodyWeight(80); // the check-in
      await app.startActive(active());
      expect(store.log, ['writeState', 'writeActive']);
      expect(store.state!['bodyweight'], contains('2026-09-30'));
      expect(app.active!.id, 'a1');
    });

    test('updates rewrite active.json only', () async {
      await app.startActive(active());
      store.log.clear();
      app.updateActive((a) => a.cur = 2);
      await Future<void>.delayed(Duration.zero);
      expect(store.log, ['writeActive']);
      expect(store.active!['cur'], 2);
      expect(app.hasUnsyncedChanges, isFalse);
    });

    test('finish writes state.json (with the workout) before deleting active.json', () async {
      await app.startActive(active());
      store.log.clear();
      await app.finishActive((d) {
        d.putWorkout(Workout.fromJson(workoutJson('a1')));
        d.putExWeight('0025', ExWeight(w: 60, d: '2026-09-30'));
      });
      expect(store.log, ['writeState', 'deleteActive']);
      expect(store.state!['workouts'], contains('a1'));
      expect(app.active, isNull);
      final data = dataOf(app);
      expect(data.workouts['a1']!.updatedAt, data.exWeights['0025']!.updatedAt);
    });

    test('discard writes state.json then deletes active.json', () async {
      await app.startActive(active());
      store.log.clear();
      await app.discardActive();
      expect(store.log, ['writeState', 'deleteActive']);
      expect(app.active, isNull);
    });

    test('a leftover active.json whose workout exists is dropped on load', () async {
      final data = LocalData();
      data.workouts['a1'] = RowRecord(data: Workout.fromJson(workoutJson('a1')), updatedAt: 1);
      store
        ..state = data.toJson()
        ..active = active().toJson();
      final loaded = await AppState.load(library: loadTestLibrary(), store: store, sessions: sessions, clock: clock);
      expect(loaded.active, isNull);
      expect(store.active, isNull);
      loaded.dispose();
    });

    test('an unfinished active.json is restored on load', () async {
      store.active = active().toJson();
      final loaded = await AppState.load(library: loadTestLibrary(), store: store, sessions: sessions, clock: clock);
      expect(loaded.active!.name, 'Push');
      loaded.dispose();
    });
  });

  group('session', () {
    test('login runs the pull-only first sync and signs in', () async {
      app.dispose();
      app = build(signedIn: false);
      server.putDoc('settings', {'unit': 'lb'});
      server.putWorkout(workoutJson('w1'));
      final events = <bool>[];
      app.addListener(() => events.add(app.isSignedIn));

      await app.login(serverUrl: 'gym.example.com', password: 'correct horse battery', deviceName: ' Pixel ');

      expect(app.isSignedIn, isTrue);
      expect(events.where((e) => e), isNotEmpty);
      expect(app.serverUrl, 'https://gym.example.com');
      expect(sessions.session.token, 'tok');
      expect(sessions.session.deviceName, 'Pixel');
      expect(app.settings.unit, 'lb');
      expect(app.workouts.single.id, 'w1');
      expect(server.requests.first['method'], 'GET');
      await app.flush();
      expect(dataOf(app).needsInitialSync, isFalse);
    });

    test('a wrong password throws UnauthorizedException and stays signed out', () async {
      app.dispose();
      app = build(signedIn: false);
      await expectLater(
        app.login(serverUrl: 'https://gym.example.com', password: 'nope', deviceName: 'x'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(app.isSignedIn, isFalse);
      expect(sessions.session.token, isNull);
    });

    test('a 401 during sync signs out but keeps local data and dirty sets', () async {
      app.saveWorkout(Workout.fromJson(workoutJson('w1')));
      handlers['POST /api/sync'] = (_) async => http.Response('{"error":"revocado"}', 401);

      await app.sync();

      expect(app.isSignedIn, isFalse);
      expect(app.workouts.single.id, 'w1');
      expect(app.hasUnsyncedChanges, isTrue);
      expect(app.serverUrl, 'https://gym.example.com', reason: 'kept to prefill the login form');
    });

    test('offline sync keeps dirty items and reports the status', () async {
      app.saveWorkout(Workout.fromJson(workoutJson('w1')));
      handlers['POST /api/sync'] = (_) async => throw http.ClientException('offline');

      await app.sync();

      expect(app.syncStatus, SyncStatus.offline);
      expect(app.lastSyncError, isNotNull);
      expect(app.hasUnsyncedChanges, isTrue);
    });

    test('logout asks when changes cannot be pushed, and clears everything when confirmed', () async {
      app.saveWorkout(Workout.fromJson(workoutJson('w1')));
      handlers['POST /api/sync'] = (_) async => throw http.ClientException('offline');

      expect(await app.logout(confirmUnsynced: () async => false), isFalse);
      expect(app.isSignedIn, isTrue);

      expect(await app.logout(confirmUnsynced: () async => true), isTrue);
      expect(app.isSignedIn, isFalse);
      expect(app.workouts, isEmpty);
      expect(store.state, isNull);
      expect(sessions.session.token, isNull);
    });
  });

  group('proposals', () {
    Proposal pending({String unit = 'kg'}) =>
        Proposal(id: 'p1', kind: 'changes', status: 'pending', unit: unit, extra: {'changes': [], 'notes': []});

    test('resolve sends only the changed docs with their draft base seqs and commits the reply', () async {
      http.Request? sent;
      handlers['POST /api/proposals/p1/resolve'] = (r) async {
        sent = r;
        return http.Response(
          jsonEncode({
            'proposal': {...pending().toJson(), 'status': 'applied'},
            'docs': [
              {'key': 'coach', 'data': (jsonDecode(r.body)['docs'][0]['data']), 'updatedAt': 77, 'seq': 12},
            ],
          }),
          200,
        );
      };
      final draft = app.beginProposalDraft();
      draft.coach.lastReview = {'at': 5};

      final result = await app.resolveProposal(pending(), outcome: 'dismissed', rejected: ['c1'], draft: draft);

      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      expect(body['outcome'], 'dismissed');
      expect(body['rejected'], ['c1']);
      expect(body['docs'], hasLength(1));
      expect(body['docs'][0]['key'], 'coach');
      expect(body['docs'][0]['baseSeq'], 0);
      expect(result.status, 'applied');
      expect(app.coach.lastReviewAt, 5);
      expect(app.proposalById('p1')!.status, 'applied');
      await app.flush();
      expect(dataOf(app).docs[DocKey.coach]!.baseSeq, 12);
    });

    test('a plan edit made while a resolve is in flight is replaced by the commit, with a notice', () async {
      final notices = <SyncNotice>[];
      final sub = app.notices.listen(notices.add);
      final release = Completer<void>();
      handlers['POST /api/proposals/p1/resolve'] = (r) async {
        await release.future;
        return http.Response(
          jsonEncode({
            'proposal': {...pending().toJson(), 'status': 'applied'},
            'docs': [
              {'key': 'plan', 'data': jsonDecode(r.body)['docs'][0]['data'], 'updatedAt': 77, 'seq': 12},
            ],
          }),
          200,
        );
      };
      final draft = app.beginProposalDraft()..plan.week['1'] = 'from-claude';
      final resolving = app.resolveProposal(pending(), outcome: 'applied', accepted: ['c1'], draft: draft);
      await Future<void>.delayed(Duration.zero);
      app.updatePlan((p) => p.week['3'] = 'edited-meanwhile');
      release.complete();
      await resolving;
      await Future<void>.delayed(Duration.zero);

      expect(app.plan.week, {'1': 'from-claude'});
      expect(notices.whereType<DraftOverwrittenNotice>().single.key, DocKey.plan);
      await sub.cancel();
    });

    test('accepting a proposal written for another unit is refused locally', () async {
      await expectLater(
        app.resolveProposal(
          pending(unit: 'lb'),
          outcome: 'applied',
          draft: app.beginProposalDraft(),
        ),
        throwsA(
          isA<ProposalUnitMismatch>().having(
            (e) => e.message,
            'message',
            'La propuesta usa lb; cambia la unidad o pide una nueva.',
          ),
        ),
      );
    });

    test('a 409 keeps local docs, stores the server proposal and rethrows', () async {
      handlers['POST /api/proposals/p1/resolve'] = (_) async => http.Response(
        jsonEncode({
          'error': 'Ya no está pendiente',
          'proposal': {...pending().toJson(), 'status': 'superseded'},
        }),
        409,
      );
      final draft = app.beginProposalDraft()..plan.week['1'] = 'r1';

      await expectLater(
        app.resolveProposal(pending(), outcome: 'applied', draft: draft),
        throwsA(isA<ConflictException>()),
      );

      expect(app.plan.week, isEmpty);
      expect(app.proposalById('p1')!.status, 'superseded');
    });
  });

  test('export rebuilds an openGym backup document', () {
    app.edit((d) {
      d.settings.targetW = 77;
      d.plan.routines.add(Routine(id: 'r1', name: 'A'));
      d.schedule.dayPlan['2026-10-01'] = 'rest';
      d.putWorkout(Workout.fromJson(workoutJson('w1')));
      d.putBodyWeight(BodyWeight(d: '2026-09-30', w: 78, t: 1));
      d.putExWeight('0025', ExWeight(w: 60, d: '2026-09-28'));
    });
    final s = app.exportOpenGymState();
    expect(s['targetW'], 77);
    expect(s['routines'], hasLength(1));
    expect(s['dayPlan'], {'2026-10-01': 'rest'});
    expect(s['workouts'], hasLength(1));
    expect(s['bodyweight'], hasLength(1));
    expect(s['exWeights'], {
      '0025': {'w': 60, 'd': '2026-09-28'},
    });
    expect(s['coach']['profile'], isNull, reason: 'athlete never saved');
    expect(s['coach']['cadence'], 'off');
    expect(s['active'], isNull);
  });
}
