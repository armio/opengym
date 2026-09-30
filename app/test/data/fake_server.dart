import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opengym/data/library.dart';
import 'package:opengym/data/models/json.dart';
import 'package:opengym/data/sync_protocol.dart';

/// An in-memory Worker implementing the sync rules of contract §3.2: compare-and-swap docs,
/// last-writer-wins rows, one seq per writing request, paging at [pageSize] rows (whole seq
/// groups), pushed items always echoed, conflicts and rejections reported.
class FakeSyncServer implements SyncApi {
  FakeSyncServer({this.epoch = 42, this.serverTime = 1790000000000});

  int seq = 0;
  int epoch;
  int serverTime;
  int pageSize = 500;

  /// key → `{key, data, updatedAt, seq}`.
  final Map<String, JsonMap> docs = {};

  /// Stored rows exactly as returned on the wire (`seq` included).
  final Map<String, JsonMap> workouts = {};
  final Map<String, JsonMap> bodyweight = {};
  final Map<String, JsonMap> exWeights = {};
  final Map<String, JsonMap> proposals = {};

  /// Workout ids the server refuses (reported in `rejected`).
  final Set<String> rejectWorkouts = {};

  /// Every request: `{'method': 'GET'|'POST', 'since': n, 'body': {...}}`.
  final List<JsonMap> requests = [];

  /// Runs while a request is "in flight", after the server applied it and before the client
  /// sees the response — to simulate local edits made meanwhile.
  void Function(JsonMap request)? inFlight;

  int _concurrent = 0;
  int maxConcurrent = 0;

  List<JsonMap> get posts => [
    for (final r in requests)
      if (r['method'] == 'POST') r,
  ];

  /// Writes a doc as another device would.
  void putDoc(String key, JsonMap data, {int? updatedAt}) {
    seq++;
    docs[key] = {'key': key, 'data': data, 'updatedAt': updatedAt ?? serverTime, 'seq': seq};
  }

  /// Writes a workout row as another device would.
  void putWorkout(JsonMap workout, {int? updatedAt, bool deleted = false}) {
    seq++;
    workouts[workout['id']] = {
      'id': workout['id'],
      'd': workout['d'],
      'start': workout['start'],
      'routineId': workout['routineId'],
      'data': deleted ? null : workout,
      'deleted': deleted,
      'updatedAt': updatedAt ?? serverTime,
      'seq': seq,
    };
  }

  void putBodyWeight(String d, num w, {int? updatedAt}) {
    seq++;
    bodyweight[d] = {
      'd': d,
      'w': w,
      't': updatedAt ?? serverTime,
      'deleted': false,
      'updatedAt': updatedAt ?? serverTime,
      'seq': seq,
    };
  }

  void putProposal(JsonMap proposal) {
    seq++;
    proposals[proposal['id']] = {...proposal, 'seq': seq};
  }

  /// Simulates restoring the database from a backup: new epoch, counter reset.
  void restore({required int newEpoch, int keepUpToSeq = 0}) {
    epoch = newEpoch;
    bool keep(JsonMap r) => (r['seq'] as int) <= keepUpToSeq;
    docs.removeWhere((_, r) => !keep(r));
    workouts.removeWhere((_, r) => !keep(r));
    bodyweight.removeWhere((_, r) => !keep(r));
    exWeights.removeWhere((_, r) => !keep(r));
    proposals.removeWhere((_, r) => !keep(r));
    seq = keepUpToSeq;
  }

  @override
  Future<SyncResponse> pull(int since) => _handle({'method': 'GET', 'since': since, 'body': null});

  @override
  Future<SyncResponse> push(JsonMap body) =>
      _handle({'method': 'POST', 'since': body['since'], 'body': jsonDecode(jsonEncode(body))});

  Future<SyncResponse> _handle(JsonMap request) async {
    _concurrent++;
    maxConcurrent = _concurrent > maxConcurrent ? _concurrent : maxConcurrent;
    try {
      requests.add(request);
      await Future<void>.delayed(Duration.zero);
      final json = request['method'] == 'POST'
          ? _applyPush(request['body'] as JsonMap)
          : _read(request['since'] as int, const {});
      inFlight?.call(request);
      await Future<void>.delayed(Duration.zero);
      return SyncResponse.fromJson(jsonDecode(jsonEncode(json)));
    } finally {
      _concurrent--;
    }
  }

  JsonMap _applyPush(JsonMap body) {
    final since = body['since'] as int;
    final next = seq + 1;
    var wrote = false;
    final conflicts = <JsonMap>[];
    final rejected = <JsonMap>[];
    final pushed = <String, Set<String>>{'docs': {}, 'workouts': {}, 'bodyweight': {}, 'exWeights': {}};

    for (final d in asList(body['docs']).cast<JsonMap>()) {
      final key = d['key'] as String;
      pushed['docs']!.add(key);
      final stored = docs[key];
      final ok = stored == null ? d['baseSeq'] == 0 : stored['seq'] == d['baseSeq'];
      if (!ok) {
        conflicts.add({'kind': 'doc', 'key': key});
        continue;
      }
      docs[key] = {'key': key, 'data': d['data'], 'updatedAt': d['updatedAt'], 'seq': next};
      wrote = true;
    }

    bool lww(Map<String, JsonMap> table, String key, JsonMap row) {
      final stored = table[key];
      if (stored != null && (row['updatedAt'] as int) <= (stored['updatedAt'] as int)) return false;
      table[key] = {...row, 'seq': next};
      return true;
    }

    for (final w in asList(body['workouts']).cast<JsonMap>()) {
      final id = w['id'] as String;
      pushed['workouts']!.add(id);
      if (rejectWorkouts.contains(id)) {
        rejected.add({'kind': 'workout', 'key': id, 'error': 'invalid'});
        continue;
      }
      final deleted = w['deleted'] == true;
      wrote =
          lww(workouts, id, {
            'id': id,
            'd': w['d'],
            'start': w['start'],
            'routineId': w['routineId'],
            'data': deleted ? null : w['data'],
            'deleted': deleted,
            'updatedAt': w['updatedAt'],
          }) ||
          wrote;
    }
    for (final b in asList(body['bodyweight']).cast<JsonMap>()) {
      final d = b['d'] as String;
      pushed['bodyweight']!.add(d);
      final deleted = b['deleted'] == true;
      wrote =
          lww(bodyweight, d, {
            'd': d,
            'w': deleted ? null : b['w'],
            't': deleted ? null : b['t'],
            'deleted': deleted,
            'updatedAt': b['updatedAt'],
          }) ||
          wrote;
    }
    for (final x in asList(body['exWeights']).cast<JsonMap>()) {
      final id = x['id'] as String;
      pushed['exWeights']!.add(id);
      final deleted = x['deleted'] == true;
      wrote =
          lww(exWeights, id, {
            'id': id,
            'w': deleted ? null : x['w'],
            'd': deleted ? null : x['d'],
            'deleted': deleted,
            'updatedAt': x['updatedAt'],
          }) ||
          wrote;
    }
    if (wrote) seq = next;
    return {..._read(since, pushed), 'conflicts': conflicts, 'rejected': rejected};
  }

  JsonMap _read(int since, Map<String, Set<String>> pushed) {
    final rows =
        <(String, JsonMap)>[
            for (final r in docs.values) ('docs', r),
            for (final r in workouts.values) ('workouts', r),
            for (final r in bodyweight.values) ('bodyweight', r),
            for (final r in exWeights.values) ('exWeights', r),
          ].where((e) => (e.$2['seq'] as int) > since).toList()
          ..sort((a, b) => (a.$2['seq'] as int).compareTo(b.$2['seq'] as int));

    var included = rows;
    var hasMore = false;
    var responseSeq = seq;
    if (rows.length > pageSize) {
      // Cut at a seq boundary so no row of the last included seq is left behind.
      final lastSeq = rows[pageSize - 1].$2['seq'] as int;
      included = [
        for (final r in rows)
          if ((r.$2['seq'] as int) <= lastSeq) r,
      ];
      hasMore = included.length < rows.length;
      responseSeq = lastSeq;
    }
    final out = <String, List<JsonMap>>{'docs': [], 'workouts': [], 'bodyweight': [], 'exWeights': []};
    for (final (table, row) in included) {
      out[table]!.add(row);
    }
    // Pushed items are always echoed with their current server version.
    void echo(String table, Map<String, JsonMap> store, String keyField) {
      for (final key in pushed[table] ?? const <String>{}) {
        final row = store[key];
        if (row != null && !out[table]!.any((r) => r[keyField] == key)) out[table]!.add(row);
      }
    }

    echo('docs', docs, 'key');
    echo('workouts', workouts, 'id');
    echo('bodyweight', bodyweight, 'd');
    echo('exWeights', exWeights, 'id');
    return {
      'seq': responseSeq,
      'epoch': epoch,
      'serverTime': serverTime,
      'hasMore': hasMore,
      ...out,
      'proposals': [
        for (final p in proposals.values)
          if ((p['seq'] as int) > since) p,
      ],
      'conflicts': [],
      'rejected': [],
    };
  }

  /// An `http.Client` serving `/api/*` from this fake: login, sync, proposal resolve/revert,
  /// logout. [handlers] override or add routes (`'POST /api/reset'` → handler).
  MockClient httpClient({
    String password = 'correct horse battery',
    Map<String, Future<http.Response> Function(http.Request)>? handlers,
    List<http.Request>? log,
  }) => MockClient((request) async {
    log?.add(request);
    final route = '${request.method} ${request.url.path}';
    final custom = handlers?[route];
    if (custom != null) return custom(request);
    if (request.url.path != '/api/auth/login' && request.headers['authorization'] != 'Bearer tok') {
      return _json(401, {'error': 'No autorizado'});
    }
    switch (route) {
      case 'POST /api/auth/login':
        final body = jsonDecode(request.body) as JsonMap;
        if (body['password'] != password) return _json(401, {'error': 'Contraseña incorrecta'});
        return _json(200, {'token': 'tok', 'deviceId': 'd0123456789abcdef'});
      case 'POST /api/auth/logout':
        return _json(200, {'ok': true});
      case 'GET /api/sync':
        final since = int.parse(request.url.queryParameters['since']!);
        requests.add({'method': 'GET', 'since': since, 'body': null});
        return _json(200, _read(since, const {}));
      case 'POST /api/sync':
        final body = jsonDecode(request.body) as JsonMap;
        requests.add({'method': 'POST', 'since': body['since'], 'body': body});
        return _json(200, _applyPush(body));
    }
    return _json(404, {'error': 'not found'});
  });

  static http.Response _json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
}

/// The real catalogue, loaded once from `assets/exercises.json`.
ExerciseLibrary loadTestLibrary() => _library ??= ExerciseLibrary.fromJson(
  jsonDecode(File('assets/exercises.json').readAsStringSync()) as List<dynamic>,
);
ExerciseLibrary? _library;

/// A minimal workout JSON for tests.
JsonMap workoutJson(
  String id, {
  String d = '2026-09-28',
  int start = 1790618820000,
  String? routineId = 'r1',
  num w = 60,
}) => {
  'id': id,
  'd': d,
  'start': start,
  'end': start + 3600000,
  'routineId': routineId,
  'name': 'Push',
  'bw': null,
  'entries': [
    {
      'id': '0025',
      'sets': [
        {'w': w, 'r': 8, 'done': true},
      ],
      'topW': null,
      'target': {'id': '0025', 'sets': 1, 'mode': 'reps', 'reps': 8},
    },
  ],
  'prs': <String>[],
  'vol': w * 8,
};
