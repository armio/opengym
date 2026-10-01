// TEMPORARY: renders the Coach screens to PNGs for a visual check. Delete before finishing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opengym/data/app_state.dart';
import 'package:opengym/ui/screens/coach/coach_screen.dart';
import 'package:opengym/ui/shell.dart';
import 'package:opengym/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coach_harness.dart';

const _out = '/tmp/claude-0/-home-user-opengym/a5e37640-33d1-5f52-b661-3bd12c87045b/scratchpad/shots/coach';
const _fonts = '/opt/flutter-sdk/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFonts() async {
  Future<ByteData> read(String f) async => ByteData.sublistView(await File('$_fonts/$f').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Light']) {
    roboto.addFont(read('Roboto-$w.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'))).load();
}

final _key = GlobalKey();

Future<void> _pump(WidgetTester tester, CoachHarness h, {double height = 844}) async {
  tester.view
    ..physicalSize = Size(390, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: h.app),
          ChangeNotifierProvider<ShellController>.value(value: h.shell),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(brightness: Brightness.dark),
          home: const CoachScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<CoachHarness> _seeded({bool withLog = true, bool claudeProfile = false}) async {
  final h = CoachHarness();
  h.server.putDoc('plan', planJson());
  h.addProposal(planProposal(iteration: 2));
  h.addProposal({...changesProposal(planHash: 'ffffffffffffffff'), 'createdAt': createdAt - 86400000});
  h.addProposal({...readingProposal(), 'createdAt': createdAt - 2 * 86400000});
  if (withLog) {
    h.addProposal({
      'id': 'p0',
      'kind': 'changes',
      'status': 'applied',
      'changes': [
        {
          'id': 'c2',
          'type': 'reps',
          'target': {'routineId': 'r2', 'exId': '0043'},
          'before': 6,
          'after': 8,
        },
      ],
      'notes': [],
    });
    h.server.putDoc('coach', {
      'log': [
        {
          'id': 'l1',
          'kind': 'create',
          'at': createdAt - 20 * 86400000,
          'proposalId': 'pOld',
          'summary': 'Plan de tres días.',
          'routines': 3,
          'iteration': 1,
        },
        {
          'id': 'l2',
          'kind': 'review',
          'at': createdAt - 5 * 86400000,
          'proposalId': 'p0',
          'summary': 'Tu sentadilla se estancó: bajamos una serie y subimos el descanso.',
          'evidence': {'from': '2026-08-01', 'to': '2026-09-15', 'sessions': 14},
          'notes': ['Duerme más de 7 horas si puedes.'],
          'decisions': [
            {
              'id': 'c1',
              'type': 'sets',
              'target': {'routineId': 'r2', 'exId': '0043'},
              'before': 5,
              'after': 4,
              'why': 'Tres sesiones fallando la última serie.',
              'status': 'accepted',
            },
            {'id': 'c2', 'type': 'reps', 'why': 'Rango más amplio.', 'status': 'rejected'},
            {'id': 'c9', 'type': 'reps', 'why': 'Sin propuesta local.', 'status': 'rejected'},
            {'id': 'c3', 'type': 'week', 'why': 'Mover el viernes.', 'status': 'stale'},
          ],
        },
      ],
      'snapshots': [
        {
          'at': createdAt - 5 * 86400000,
          'proposalId': 'p0',
          'label': 'Antes de los cambios del Coach',
          'routines': [],
          'week': {},
        },
      ],
      'lastReview': {'at': createdAt - 5 * 86400000},
    });
  }
  if (claudeProfile) {
    h.server.putDoc('athlete', {
      'goal': 'muscle',
      'experience': 'returning',
      'daysPerWeek': 7,
      'preferredDays': [1, 3, 5],
      'sessionMin': 120,
      'equipment': ['dumbbell', 'rope'],
      'limitations': 'Hombro derecho delicado.',
      'likes': '',
      'dislikes': '',
      'notes': '',
      'savedAt': createdAt,
      'updatedBy': 'claude',
    });
  }
  await h.sync();
  return h;
}

Future<void> _dispose(WidgetTester tester, CoachHarness h) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox());
  h.app.dispose();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shots', (tester) async {
    await tester.runAsync(_loadFonts);

    final h = await _seeded(claudeProfile: true);
    await _pump(tester, h, height: 2700);
    await _shot(tester, '01_coach_full');

    await _pump(tester, h);
    await tester.tap(find.text('Tu plan está listo'));
    await tester.pumpAndSettle();
    await _shot(tester, '03_plan_proposal_fold');
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();

    await _pump(tester, h, height: 1500);
    await tester.tap(find.text('Sugerencias listas'));
    await tester.pumpAndSettle();
    await _shot(tester, '04_change_set');
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();

    await _pump(tester, h, height: 2700);
    await tester.tap(find.text('Revisó tu entrenamiento'));
    await tester.pumpAndSettle();
    await _shot(tester, '05_history_sheet');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await _pump(tester, h);
    await tester.tap(find.text('Ver perfil'));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 6; i++) {
      await _shot(tester, '06_intake_$i');
      if (i < 6) {
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
      }
    }
    await _dispose(tester, h);

    // Unit mismatch + offline.
    final lb = CoachHarness();
    lb.server.putDoc('plan', planJson());
    lb.addProposal(planProposal(unit: 'lb'));
    await lb.sync();
    lb.handlers['GET /api/sync'] = (_) async => throw http.ClientException('offline');
    lb.handlers['POST /api/sync'] = (_) async => throw http.ClientException('offline');
    await lb.sync();
    await _pump(tester, lb);
    await _shot(tester, '08_offline');
    await tester.tap(find.text('Tu plan está listo'));
    await tester.pumpAndSettle();
    await _shot(tester, '09_unit_mismatch');
    await _dispose(tester, lb);

    final empty = CoachHarness();
    await _pump(tester, empty, height: 1900);
    await _shot(tester, '07_empty');
    await _dispose(tester, empty);
  });
}
