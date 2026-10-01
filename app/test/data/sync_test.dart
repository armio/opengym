import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/api_client.dart';
import 'package:opengym/data/clock.dart';
import 'package:opengym/data/local_data.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/data/sync.dart';
import 'package:opengym/data/sync_protocol.dart';

import 'fake_server.dart';

/// Edits a local doc the way AppState does: new data, new stamp, dirty.
void editDoc<T extends JsonModel>(LocalData data, DocKey key, int updatedAt, void Function(T doc) fn) {
  final rec = data.docs[key]!;
  final copy = key.parse(rec.data.toJson()) as T;
  fn(copy);
  rec
    ..data = copy
    ..updatedAt = updatedAt;
  data.dirtyDocs.add(key);
}

void putLocalWorkout(LocalData data, JsonMap json, int updatedAt) {
  data.workouts[json['id']] = RowRecord(data: Workout.fromJson(json), updatedAt: updatedAt);
  data.dirtyWorkouts.add(json['id']);
}

PlanDoc planOf(LocalData d) => d.doc<PlanDoc>(DocKey.plan);

void main() {
  late FakeSyncServer server;
  late LocalData data;
  late SyncService sync;
  late FakeClock clock;

  setUp(() {
    server = FakeSyncServer();
    data = LocalData()..epoch = server.epoch;
    clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(server.serverTime));
    sync = SyncService(data: data, api: server, clock: clock);
  });

  test('pushes dirty docs and rows, adopts the server versions and clears dirty', () async {
    editDoc<PlanDoc>(data, DocKey.plan, 1000, (p) => p.week['1'] = 'r1');
    putLocalWorkout(data, workoutJson('w1'), 1000);
    data.bodyWeight['2026-09-30'] = RowRecord(data: BodyWeight(d: '2026-09-30', w: 78.7, t: 9), updatedAt: 1000);
    data.dirtyBodyWeight.add('2026-09-30');

    final report = await sync.sync();

    expect(report.notices, isEmpty);
    expect(data.hasDirty, isFalse);
    expect(server.docs['plan']!['data']['week'], {'1': 'r1'});
    expect(server.workouts['w1']!['start'], 1790618820000);
    expect(server.bodyweight['2026-09-30']!['w'], 78.7);
    expect(data.docs[DocKey.plan]!.baseSeq, server.docs['plan']!['seq']);
    expect(data.lastSeq, server.seq);
    // Docs are pushed with baseSeq 0 (new) and their updatedAt.
    final pushed = server.posts.first['body'] as JsonMap;
    expect(pushed['docs'][0], containsPair('baseSeq', 0));
    expect(pushed['docs'][0], containsPair('updatedAt', 1000));
    expect(pushed['workouts'][0], containsPair('d', '2026-09-28'));
    expect(pushed['workouts'][0], containsPair('routineId', 'r1'));
  });

  test('a doc changed on another device wins: the local edit is discarded with a notice', () async {
    server.putDoc('plan', {
      'routines': [],
      'week': {'2': 'theirs'},
      'customEx': [],
    });
    editDoc<PlanDoc>(data, DocKey.plan, 1000, (p) => p.week['1'] = 'mine'); // baseSeq 0: stale

    final report = await sync.sync();

    expect(report.conflicts, [DocKey.plan]);
    expect(report.notices.single.message, 'Se descartó un cambio sin sincronizar: el plan cambió en otro dispositivo.');
    expect(planOf(data).week, {'2': 'theirs'});
    expect(data.dirtyDocs, isEmpty);
    expect(data.docs[DocKey.plan]!.baseSeq, server.docs['plan']!['seq']);
  });

  test('a doc edited while its push is in flight stays dirty and is pushed next round', () async {
    editDoc<PlanDoc>(data, DocKey.plan, 1000, (p) => p.week['1'] = 'first');
    server.inFlight = (request) {
      if (server.posts.length == 1) editDoc<PlanDoc>(data, DocKey.plan, 2000, (p) => p.week['3'] = 'second');
    };

    final report = await sync.sync();

    expect(report.conflicts, isEmpty);
    expect(server.posts, hasLength(2));
    final second = server.posts[1]['body'] as JsonMap;
    // Based on the version this device just wrote, so no conflict.
    expect(second['docs'][0]['baseSeq'], 1);
    expect(server.docs['plan']!['data']['week'], {'1': 'first', '3': 'second'});
    expect(planOf(data).week, {'1': 'first', '3': 'second'});
    expect(data.hasDirty, isFalse);
  });

  test('a row edited while in flight keeps the local copy and is pushed again', () async {
    putLocalWorkout(data, workoutJson('w1', w: 60), 1000);
    server.inFlight = (_) {
      if (server.posts.length == 1) putLocalWorkout(data, workoutJson('w1', w: 65), 2000);
    };

    await sync.sync();

    expect(server.posts, hasLength(2));
    expect(server.workouts['w1']!['updatedAt'], 2000);
    expect(data.workouts['w1']!.data.entries.single.sets.single.w, 65);
    expect(data.dirtyWorkouts, isEmpty);
  });

  test('rejected items stop being dirty, keep their local data and raise a notice', () async {
    server.rejectWorkouts.add('bad');
    putLocalWorkout(data, workoutJson('bad'), 1000);
    putLocalWorkout(data, workoutJson('good'), 1000);

    final report = await sync.sync();

    expect(report.rejected.single.key, 'bad');
    expect(report.notices.whereType<RejectedNotice>().single.message, '1 elemento no se pudo sincronizar');
    expect(data.dirtyWorkouts, isEmpty);
    expect(data.workouts['bad'], isNotNull);
    expect(server.workouts.containsKey('bad'), isFalse);
    expect(server.workouts.containsKey('good'), isTrue);
  });

  test('pages with hasMore until everything is pulled', () async {
    server.pageSize = 50;
    for (var i = 0; i < 120; i++) {
      server.putWorkout(workoutJson('w$i', start: 1790618820000 + i));
    }

    await sync.sync();

    expect(server.requests.map((r) => r['method']), ['GET', 'GET', 'GET']);
    expect(server.requests.map((r) => r['since']), [0, 50, 100]);
    expect(data.workouts, hasLength(120));
    expect(data.lastSeq, server.seq);
  });

  test('rows from other devices are adopted unless dirty here', () async {
    server.putWorkout(workoutJson('shared', w: 100), updatedAt: 500);
    server.putWorkout(workoutJson('theirs', w: 50), updatedAt: 500);
    server.putWorkout(workoutJson('gone'), updatedAt: 500, deleted: true);
    data.workouts['gone'] = RowRecord(data: Workout.fromJson(workoutJson('gone')), updatedAt: 1);
    putLocalWorkout(data, workoutJson('shared', w: 110), 900); // newer local edit

    await sync.sync();

    expect(data.workouts['theirs']!.data.entries.single.sets.single.w, 50);
    expect(data.workouts.containsKey('gone'), isFalse);
    // Last writer wins on the server: the newer local edit survives everywhere.
    expect(data.workouts['shared']!.data.entries.single.sets.single.w, 110);
    expect(server.workouts['shared']!['updatedAt'], 900);
  });

  test('an older local edit loses to the server copy (LWW) and is replaced', () async {
    server.putWorkout(workoutJson('w1', w: 100), updatedAt: 5000);
    putLocalWorkout(data, workoutJson('w1', w: 90), 4000);

    await sync.sync();

    expect(data.workouts['w1']!.data.entries.single.sets.single.w, 100);
    expect(data.workouts['w1']!.updatedAt, 5000);
    expect(data.dirtyWorkouts, isEmpty);
  });

  test('a new epoch resets the cursor and resends everything', () async {
    editDoc<PlanDoc>(data, DocKey.plan, 1000, (p) => p.week['1'] = 'r1');
    putLocalWorkout(data, workoutJson('w1'), 1000);
    await sync.sync();
    expect(data.hasDirty, isFalse);

    server.restore(newEpoch: 7); // database recreated empty
    final requestsBefore = server.requests.length;
    final report = await sync.sync();

    expect(data.epoch, 7);
    expect(server.docs['plan']!['data']['week'], {'1': 'r1'});
    expect(server.workouts.containsKey('w1'), isTrue);
    expect(data.hasDirty, isFalse);
    // Docs the owner did not touch since the last sync are not reported as conflicts.
    expect(report.conflicts, isEmpty);
    final resent = server.requests.skip(requestsBefore).where((r) => r['method'] == 'POST').first['body'] as JsonMap;
    expect(resent['since'], 0);
    expect(resent['docs'][0]['baseSeq'], 0);
    // Untouched default docs are not pushed.
    expect([for (final d in resent['docs']) d['key']], ['plan']);
  });

  test('a counter that went backwards is treated as a restored database', () async {
    for (var i = 0; i < 5; i++) {
      server.putWorkout(workoutJson('w$i'));
    }
    await sync.sync();
    expect(data.lastSeq, 5);

    server.restore(newEpoch: server.epoch, keepUpToSeq: 2); // same epoch, counter back to 2
    await sync.sync();

    expect(data.lastSeq, server.seq);
    expect(server.workouts.keys, containsAll(['w0', 'w1', 'w2', 'w3', 'w4']));
  });

  group('first sync after login', () {
    setUp(() => data.needsInitialSync = true);

    test('is pull-only, then pushes what was already dirty', () async {
      server.putWorkout(workoutJson('server1'));
      server.putDoc('settings', {'unit': 'lb'});
      putLocalWorkout(data, workoutJson('local-dirty'), 1000); // e.g. logged before a 401

      await sync.initialSync();

      expect(server.requests.first['method'], 'GET');
      expect(server.requests.first['since'], 0);
      expect(server.requests.indexWhere((r) => r['method'] == 'POST'), greaterThan(0));
      expect(data.doc<Settings>(DocKey.settings).unit, 'lb');
      expect(data.workouts.keys, containsAll(['server1', 'local-dirty']));
      expect(server.workouts.containsKey('local-dirty'), isTrue);
      expect(data.needsInitialSync, isFalse);
    });

    test('asks before uploading rows only this device has when the server has data', () async {
      server.putWorkout(workoutJson('server1'));
      data.workouts['orphan'] = RowRecord(data: Workout.fromJson(workoutJson('orphan')), updatedAt: 3);
      data.bodyWeight['2026-01-01'] = RowRecord(data: BodyWeight(d: '2026-01-01', w: 80, t: 1), updatedAt: 3);
      LocalOnlyData? asked;

      await sync.initialSync(
        confirmUpload: (summary) async {
          asked = summary;
          return false;
        },
      );

      expect(asked!.workouts, 1);
      expect(asked!.bodyWeights, 1);
      expect(data.workouts.containsKey('orphan'), isFalse);
      expect(data.bodyWeight, isEmpty);
      expect(server.workouts.containsKey('orphan'), isFalse);
    });

    test('uploads them when the owner agrees', () async {
      server.putWorkout(workoutJson('server1'));
      data.workouts['orphan'] = RowRecord(data: Workout.fromJson(workoutJson('orphan')), updatedAt: 3);

      await sync.initialSync(confirmUpload: (_) async => true);

      expect(server.workouts.containsKey('orphan'), isTrue);
      expect(data.dirtyWorkouts, isEmpty);
    });

    test('uploads them without asking when the server is empty', () async {
      data.workouts['orphan'] = RowRecord(data: Workout.fromJson(workoutJson('orphan')), updatedAt: 3);
      var asked = false;

      await sync.initialSync(confirmUpload: (_) async => asked = true);

      expect(asked, isFalse);
      expect(server.workouts.containsKey('orphan'), isTrue);
    });

    test('reports progress per page', () async {
      server.pageSize = 10;
      for (var i = 0; i < 25; i++) {
        server.putWorkout(workoutJson('w$i'));
      }
      final progress = <SyncProgress>[];

      await sync.initialSync(onProgress: progress.add);

      expect(progress.map((p) => p.pages), [1, 2, 3]);
      expect(progress.last.items, 25);
    });
  });

  test('clockOffset follows serverTime with exponential smoothing', () async {
    server.serverTime = clock.nowMs() + 600000; // server 10 min ahead
    await sync.sync();
    expect(data.clockOffset, 600000);

    server.serverTime = clock.nowMs(); // then in agreement
    await sync.sync();
    expect(data.clockOffset, 420000); // 0.7 × 600000 + 0.3 × 0
  });

  test('pushes in chunks: docs first, at most 100 workouts per request', () async {
    editDoc<Settings>(data, DocKey.settings, 1000, (s) => s.unit = 'lb');
    for (var i = 0; i < 250; i++) {
      putLocalWorkout(data, workoutJson('w$i', start: 1790618820000 + i), 1000);
    }

    await sync.sync();

    final sizes = [for (final p in server.posts) (p['body'] as JsonMap)['workouts']?.length ?? 0];
    expect(sizes, [100, 100, 50]);
    expect((server.posts.first['body'] as JsonMap)['docs'], hasLength(1));
    expect(server.workouts, hasLength(250));
    expect(data.hasDirty, isFalse);
  });

  test('sync calls are serialised and coalesced', () async {
    putLocalWorkout(data, workoutJson('w1'), 1000);
    final a = sync.sync();
    putLocalWorkout(data, workoutJson('w2'), 1000);
    final b = sync.sync();

    expect(identical(await a, await b), isTrue);
    expect(server.maxConcurrent, 1);
    expect(server.workouts.keys, containsAll(['w1', 'w2']));
  });

  test('the athlete doc is not pushed while savedAt is null', () async {
    editDoc<AthleteProfile>(data, DocKey.athlete, 1000, (a) => a.notes = 'draft');
    await sync.sync();
    expect(server.docs.containsKey('athlete'), isFalse);

    editDoc<AthleteProfile>(data, DocKey.athlete, 2000, (a) => a.savedAt = 2000);
    await sync.sync();
    expect(server.docs['athlete']!['data']['notes'], 'draft');
  });

  test('a local deletion is pushed as a tombstone, then forgotten', () async {
    putLocalWorkout(data, workoutJson('w1'), 1000);
    await sync.sync();

    data.workouts['w1']!
      ..deleted = true
      ..updatedAt = 2000;
    data.dirtyWorkouts.add('w1');
    await sync.sync();

    final item = (server.posts.last['body'] as JsonMap)['workouts'][0] as JsonMap;
    expect(item, {
      'id': 'w1',
      'd': '2026-09-28',
      'start': 1790618820000,
      'routineId': 'r1',
      'updatedAt': 2000,
      'deleted': true,
    });
    expect(server.workouts['w1']!['deleted'], isTrue);
    expect(data.workouts.containsKey('w1'), isFalse);
  });

  test('proposals are replaced by id', () async {
    server.putProposal({'id': 'p1', 'kind': 'nochange', 'status': 'pending', 'reading': 'Vas bien', 'createdAt': 1});
    await sync.sync();
    expect(data.proposals['p1']!.reading, 'Vas bien');

    server.putProposal({'id': 'p1', 'kind': 'nochange', 'status': 'expired', 'reading': 'Vas bien', 'createdAt': 1});
    await sync.sync();
    expect(data.proposals['p1']!.status, 'expired');
    expect(data.proposals, hasLength(1));
  });

  test('errors propagate and keep the dirty sets', () async {
    putLocalWorkout(data, workoutJson('w1'), 1000);
    final failing = SyncService(data: data, api: _OfflineApi(), clock: clock);

    await expectLater(failing.sync(), throwsA(isA<OfflineException>()));
    expect(data.dirtyWorkouts, {'w1'});
    expect(failing.isRunning, isFalse);
  });

  test('backoff doubles from 2 s up to 5 min', () {
    expect(syncBackoff(1), const Duration(seconds: 2));
    expect(syncBackoff(2), const Duration(seconds: 4));
    expect(syncBackoff(5), const Duration(seconds: 32));
    expect(syncBackoff(20), const Duration(minutes: 5));
  });
  test('a pull answered before a newer commit never rolls a doc back to an older seq', () async {
    server.putDoc('plan', {
      'routines': [],
      'week': {'1': 'old'},
      'customEx': [],
    });
    await sync.sync();
    final oldSeq = data.docs[DocKey.plan]!.baseSeq;
    // A resolve committed a newer plan (seq above the one a slow pull is about to deliver).
    data.docs[DocKey.plan]!
      ..data = PlanDoc.fromJson({
        'routines': [],
        'week': {'1': 'new'},
        'customEx': [],
      })
      ..baseSeq = oldSeq + 5;
    data.lastSeq = 0; // the slow pull re-delivers the old version
    await sync.sync();
    expect(planOf(data).week, {'1': 'new'});
    expect(data.docs[DocKey.plan]!.baseSeq, oldSeq + 5);
  });

  test('a new database clears proposals it no longer has', () async {
    server.putProposal({
      'id': 'pgone',
      'kind': 'nochange',
      'status': 'pending',
      'createdAt': 1,
      'expiresAt': 2,
      'unit': 'kg',
      'summary': 'x',
      'reading': 'x',
    });
    await sync.sync();
    expect(data.proposals.keys, contains('pgone'));
    server.restore(newEpoch: 99);
    await sync.sync();
    expect(data.proposals, isEmpty);
  });
}

class _OfflineApi implements SyncApi {
  @override
  Future<SyncResponse> pull(int since) async => throw const OfflineException();

  @override
  Future<SyncResponse> push(JsonMap body) async => throw const OfflineException();
}
