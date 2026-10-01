import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/settings/backup_files.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../data/fake_server.dart';
import '../../widgets/test_app.dart';
import 'settings_harness.dart';

void main() {
  Finder inDialog(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);
  Uint8List bytesOf(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

  group('backup files', () {
    test('are named after the local date and pretty-printed', () {
      expect(backupFileName(DateTime(2026, 9, 30, 23, 59)), 'opengym-backup-2026-09-30.json');
      final text = utf8.decode(encodeBackup({'unit': 'kg', 'workouts': <Object>[]}));
      expect(text, '{\n  "unit": "kg",\n  "workouts": []\n}');
    });

    test('decode only openGym backups', () {
      expect(decodeBackup(bytesOf({'workouts': [], 'routines': []})), {'workouts': [], 'routines': []});
      String reason(Object bytes) {
        try {
          decodeBackup(bytes is Uint8List ? bytes : bytesOf(bytes));
          return 'ok';
        } on BackupFormatException catch (e) {
          return e.message;
        }
      }

      expect(reason({'workouts': []}), 'no es una copia de openGym');
      expect(reason({'workouts': {}, 'routines': []}), 'no es una copia de openGym');
      expect(reason([1, 2]), 'no es una copia de openGym');
      expect(reason(Uint8List.fromList(utf8.encode('{nope'))), 'el archivo no es un JSON válido');
      expect(reason(Uint8List(maxBackupBytes + 1)), 'la copia supera los 20 MB');
      final withBom = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...bytesOf({'workouts': [], 'routines': []}),
      ]);
      expect(reason(withBom), 'ok');
    });
  });

  testWidgets('"Exportar copia" shares the openGym document rebuilt from local data', (tester) async {
    final harness = SettingsHarness();
    final app = harness.app
      ..updatePlan((p) => p.routines.add(Routine(id: 'r1', name: 'Empuje')))
      ..saveWorkout(Workout.fromJson(workoutJson('w1')))
      ..setBodyWeight(80);
    await pumpSettings(tester, harness);

    await tester.tap(find.text('Exportar copia (JSON)'));
    await tester.pumpAndSettle();

    final (name, bytes) = harness.files.shared.single;
    expect(name, 'opengym-backup-2026-09-30.json');
    final state = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(state['unit'], 'kg');
    expect([for (final r in state['routines'] as List) r['name']], ['Empuje']);
    expect([for (final w in state['workouts'] as List) w['id']], ['w1']);
    expect(state['bodyweight'], [
      {'d': '2026-09-30', 'w': 80, 't': app.clock.nowMs()},
    ]);
    expect(state['active'], isNull);
    expect((state['coach'] as Map)['cadence'], 'off');
    expect(find.text('Copia exportada'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('"Importar copia" rejects other files, confirms, then replaces through the server', (tester) async {
    final harness = SettingsHarness();
    final app = harness.app;
    await pumpSettings(tester, harness);

    harness.files.toPick = bytesOf({'hello': 'world'});
    await tester.tap(find.text('Importar copia de openGym'));
    await tester.pumpAndSettle();
    expect(find.text('Importación fallida: no es una copia de openGym'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    harness.files.toPick = bytesOf({
      'unit': 'kg',
      'routines': [
        {'id': 'r1', 'name': 'Empuje', 'ex': []},
        {'id': 'r2', 'name': 'Tirón', 'ex': []},
      ],
      'workouts': [workoutJson('w1')],
    });
    await tester.tap(find.text('Importar copia de openGym'));
    await tester.pumpAndSettle();
    expect(find.text('¿Importar copia?'), findsOneWidget);
    await tester.tap(inDialog(find.text('Importar')));
    await tester.pumpAndSettle();

    expect(harness.importedBody?['mode'], 'replace');
    expect(app.plan.routines.map((r) => r.name), ['Empuje', 'Tirón'], reason: 'pulled back from the server');
    expect(app.workoutById('w1'), isNotNull);
    expect(find.text('Copia importada: 1 entreno, 2 rutinas'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('"Borrar todo" unlocks only after typing BORRAR, then wipes server and device', (tester) async {
    final harness = SettingsHarness();
    final app = harness.app..saveWorkout(Workout.fromJson(workoutJson('w1')));
    await pumpSettings(tester, harness);
    await tester.pump(const Duration(seconds: 3)); // the workout reaches the server
    expect(harness.server.workouts['w1']?['deleted'], isFalse);

    await tester.tap(find.text('Borrar todo'));
    await tester.pumpAndSettle();
    final confirm = inDialog(find.widgetWithText(AppButton, 'Borrar todo'));
    expect(tester.widget<AppButton>(confirm).onPressed, isNull);

    await tester.enterText(inDialog(find.byType(TextField)), 'borrar');
    await tester.pump();
    expect(tester.widget<AppButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(harness.routes, contains('POST /api/reset'));
    expect(app.workouts, isEmpty);
    expect(find.text('Todos los datos borrados'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('offline, import and reset report the failure and change nothing', (tester) async {
    final harness = SettingsHarness()..offline = true;
    final app = harness.app..updatePlan((p) => p.routines.add(Routine(id: 'r1', name: 'Mía')));
    await pumpSettings(tester, harness);

    harness.files.toPick = bytesOf({'routines': [], 'workouts': []});
    await tester.tap(find.text('Importar copia de openGym'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Importar')));
    await tester.pumpAndSettle();
    expect(find.text('Importación fallida: Sin conexión con el servidor.'), findsOneWidget);

    await tester.tap(find.text('Borrar todo'));
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)), 'BORRAR');
    await tester.pump();
    await tester.tap(inDialog(find.widgetWithText(AppButton, 'Borrar todo')));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo borrar: Sin conexión con el servidor.'), findsOneWidget);

    expect(app.plan.routines.single.name, 'Mía');
    expect(app.isSignedIn, isTrue);
    await settleAndDispose(tester, app);
  });
}
