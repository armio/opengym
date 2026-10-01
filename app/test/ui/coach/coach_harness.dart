import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opengym/data/api_client.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/clock.dart';
import 'package:opengym/data/library.dart';
import 'package:opengym/data/local_store.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/data/session_store.dart';
import 'package:opengym/engine/engine.dart';
import 'package:opengym/ui/screens/coach/coach_screen.dart';
import 'package:opengym/ui/shell.dart';
import 'package:opengym/ui/theme.dart';
import 'package:provider/provider.dart';

import '../../data/fake_server.dart';
import '../../widgets/test_app.dart';

typedef Handler = Future<http.Response> Function(http.Request request);

/// A signed-in [AppState] whose server is a [FakeSyncServer] extended with the proposal
/// endpoints of contract §4.3: resolve and revert run the guards (proposal state, each doc's
/// `seq == baseSeq`) and then write the docs and the proposal with one new seq, or answer 409
/// with the stored proposal.
class CoachHarness {
  CoachHarness() {
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
      clock: clock,
      apiFactory: (url, token) => ApiClient(
        baseUrl: url,
        token: token,
        timeZone: () async => 'Europe/Madrid',
        httpClient: server.httpClient(log: requests, handlers: handlers),
      ),
    );
  }

  final server = FakeSyncServer();
  final clock = FakeClock(DateTime(2026, 9, 30, 18));
  final requests = <http.Request>[];
  final handlers = <String, Handler>{};
  final shell = ShellController(AppTab.coach);
  late final AppState app;

  /// When true, the proposal endpoints are unreachable.
  bool offline = false;

  /// Bodies of every proposal write, in order: `(route, body)`.
  final writes = <(String, JsonMap)>[];

  JsonMap get lastWrite => writes.last.$2;

  /// Stores [proposal] on the server (as Claude would) and serves its endpoints.
  void addProposal(JsonMap proposal) {
    final id = proposal['id'] as String;
    server.putProposal({
      'status': 'pending',
      'createdAt': createdAt,
      'expiresAt': createdAt + 14 * 86400000,
      'unit': 'kg',
      'iteration': 1,
      'summary': '',
      'resolution': null,
      'resolvedAt': null,
      'revertedAt': null,
      ...proposal,
    });
    handlers['POST /api/proposals/$id/resolve'] = (r) => _write(id, r, revert: false);
    handlers['POST /api/proposals/$id/revert'] = (r) => _write(id, r, revert: true);
  }

  /// Pulls everything from the fake server.
  Future<void> sync() => app.sync();

  Future<http.Response> _write(String id, http.Request request, {required bool revert}) async {
    if (offline) throw http.ClientException('offline');
    final body = jsonDecode(request.body) as JsonMap;
    writes.add(('${request.method} ${request.url.path}', body));
    final stored = server.proposals[id]!;
    final docs = [for (final d in body['docs'] as List? ?? const []) d as JsonMap];
    if (revert ? stored['status'] != 'applied' : stored['status'] != 'pending') {
      return _json(409, {'error': 'Esta propuesta ya no está pendiente.', 'proposal': stored});
    }
    for (final d in docs) {
      if ((server.docs[d['key']]?['seq'] ?? 0) != d['baseSeq']) {
        return _json(409, {
          'error': 'Tus datos cambiaron en otro dispositivo. Sincroniza y vuelve a intentarlo.',
          'proposal': stored,
        });
      }
    }
    final seq = ++server.seq;
    final written = [
      for (final d in docs)
        server.docs[d['key'] as String] = {
          'key': d['key'],
          'data': d['data'],
          'updatedAt': server.serverTime,
          'seq': seq,
        },
    ];
    final updated = {
      ...stored,
      'seq': seq,
      if (revert)
        'revertedAt': server.serverTime
      else ...{
        'status': body['outcome'],
        'resolvedAt': server.serverTime,
        'resolution': {
          'outcome': body['outcome'],
          'accepted': body['accepted'],
          'rejected': body['rejected'],
          'stale': body['stale'],
          if (body.containsKey('schedule')) 'schedule': body['schedule'],
        },
      },
    };
    server.proposals[id] = updated;
    return _json(200, {'proposal': updated, 'docs': written});
  }

  static http.Response _json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
}

/// When the fixtures' proposals were created (before the harness clock's "now").
const createdAt = 1790000000000;

/// The owner's plan: Full body A (3 exercises) and Full body B, Monday/Wednesday/Friday.
JsonMap planJson() => {
  'routines': [
    {
      'id': 'r1',
      'name': 'Full body A',
      'emoji': 'dumbbell',
      'prog': 'linear',
      'ex': [
        {'id': '0025', 'sets': 3, 'reps': 10, 'mode': 'reps', 'weight': 60, 'prog': 'linear'},
        {'id': '0464', 'sets': 3, 'sec': 45, 'mode': 'time'},
        {'id': '0294', 'sets': 3, 'reps': 12, 'mode': 'reps'},
      ],
    },
    {
      'id': 'r2',
      'name': 'Full body B',
      'emoji': 'legs',
      'ex': [
        {'id': '0043', 'sets': 4, 'reps': 6, 'mode': 'reps', 'weight': 80},
      ],
    },
  ],
  'week': {'1': 'r1', '3': 'r2', '5': 'r1'},
  'customEx': <dynamic>[],
};

/// The fingerprint of [plan] as the Worker stores it on a proposal.
String hashOf(JsonMap plan) =>
    planHash(PlanDoc.fromJson(plan), CatalogExerciseIndex(ExerciseCatalog(loadTestLibrary(), const [])));

/// A `plan` proposal: two routines on Tuesday and Thursday, one exercise with a reason.
JsonMap planProposal({String id = 'pPlan', String unit = 'kg', int iteration = 1}) => {
  'id': id,
  'kind': 'plan',
  'unit': unit,
  'iteration': iteration,
  'summary': 'Dos días de cuerpo completo que caben en 45 minutos.',
  'bundle': {
    'opengym_plan': 1,
    'name': 'Plan de fuerza 2 días',
    'summary': 'Dos días de cuerpo completo que caben en 45 minutos.',
    'basedOn': 'tus últimas 12 semanas',
    'week': {'2': 'x1', '4': 'x2'},
    'routines': [
      {
        'id': 'x1',
        'name': 'Empuje y pierna',
        'emoji': 'barbell',
        'prog': 'linear',
        'why': 'Los básicos primero, con descanso largo.',
        'ex': [
          {'id': '0025', 'sets': 3, 'mode': 'reps', 'reps': 8, 'why': 'Tu press de banca progresa bien.'},
          {'id': '0043', 'sets': 3, 'mode': 'reps', 'reps': 6},
        ],
      },
      {
        'id': 'x2',
        'name': 'Tirón',
        'emoji': 'pullup',
        'ex': [
          {'id': '0652', 'sets': 3, 'mode': 'reps', 'reps': 8, 'why': 'Tirón vertical con tu peso.'},
          {'id': '0027', 'sets': 3, 'mode': 'reps', 'reps': 10, 'sg': 'a'},
          {'id': '0294', 'sets': 3, 'mode': 'reps', 'reps': 12, 'sg': 'a'},
        ],
      },
    ],
    'customEx': <dynamic>[],
  },
};

/// A `changes` proposal against [planJson]: c1 sets 3→4 and c2 reps 10→12 on 0025, and c3
/// written against a value the plan no longer has (stale).
JsonMap changesProposal({String id = 'pChanges', String? planHash, String unit = 'kg'}) => {
  'id': id,
  'kind': 'changes',
  'unit': unit,
  'planHash': planHash,
  'summary': 'El press de banca lleva tres sesiones estancado.',
  'evidence': {'from': '2026-08-03', 'to': '2026-09-28', 'sessions': 12},
  'changes': [
    {
      'id': 'c1',
      'type': 'sets',
      'target': {'routineId': 'r1', 'exId': '0025'},
      'before': 3,
      'after': 4,
      'why': 'Tres sesiones sin completar las repeticiones.',
    },
    {
      'id': 'c2',
      'type': 'reps',
      'target': {'routineId': 'r1', 'exId': '0025'},
      'before': 10,
      'after': 12,
      'why': 'RIR alto en las últimas series.',
    },
    {
      'id': 'c3',
      'type': 'sets',
      'target': {'routineId': 'r2', 'exId': '0043'},
      'before': 5,
      'after': 3,
      'why': 'Demasiado volumen de pierna.',
    },
  ],
  'notes': ['Tu peso lleva cuatro semanas estable: si quieres ganar, come algo más.'],
};

/// A `nochange` proposal.
JsonMap readingProposal({String id = 'pReading'}) => {
  'id': id,
  'kind': 'nochange',
  'summary': 'Todo va bien.',
  'reading': 'Tu plan funciona: has subido peso en todos los básicos. Sigue así.',
};

/// Pumps the Coach tab with [harness]'s app and shell controller on a phone-sized viewport
/// ([height] tall so long screens build without scrolling).
Future<void> pumpCoach(WidgetTester tester, CoachHarness harness, {double height = 3000}) async {
  tester.view
    ..physicalSize = Size(390, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: harness.app),
        ChangeNotifierProvider<ShellController>.value(value: harness.shell),
      ],
      child: MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: const CoachScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets toasts and debounced timers run out, then disposes the app.
Future<void> disposeHarness(WidgetTester tester, CoachHarness harness) => settleAndDispose(tester, harness.app);

/// Captures `Clipboard.setData`; returns a getter for the last copied text.
String? Function() captureClipboard(WidgetTester tester) {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return () => copied;
}
