import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/plan/plan_screen.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../widgets/test_app.dart';
import '../library/test_view.dart';

void main() {
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  Finder stepperField(String label) =>
      inSheet(find.descendant(of: find.widgetWithText(ValueStepper, label), matching: find.byType(TextField)));
  String stepperText(WidgetTester tester, String label) =>
      tester.widget<TextField>(stepperField(label)).controller!.text;

  /// Opens the sheet for [exerciseId] from a button; the result lands in [results].
  Future<List<ExerciseConfigResult?>> open(
    WidgetTester tester,
    AppState app,
    String exerciseId, {
    RoutineExercise? existing,
    Routine? routine,
    bool allowDelete = false,
  }) async {
    useTallView(tester);
    final results = <ExerciseConfigResult?>[];
    await pumpWithApp(
      tester,
      app,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: AppButton(
              'Abrir',
              onPressed: () async => results.add(
                await showExerciseConfigSheet(
                  context,
                  exercise: app.catalog.byId(exerciseId)!,
                  existing: existing,
                  routine: routine,
                  allowDelete: allowDelete,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    return results;
  }

  RoutineExercise saved(List<ExerciseConfigResult?> results) => (results.single! as ExerciseConfigSaved).config;

  testWidgets('a new reps exercise: defaults, rule "double" adds the step and the rep range', (tester) async {
    final app = testAppState();
    final routine = Routine(id: 'r', name: 'R', prog: 'off');
    final results = await open(tester, app, '0025', routine: routine);

    expect(inSheet(find.text('Barbell Bench Press')), findsOneWidget);
    expect(inSheet(find.text('Pectorales')), findsOneWidget);
    expect(
      [stepperText(tester, 'Series'), stepperText(tester, 'Reps'), stepperText(tester, 'Peso (kg)')],
      ['3', '10', '0'],
    );
    expect(inSheet(find.text('Seguir la rutina (Sin progresión automática)')), findsOneWidget);
    expect(inSheet(find.text('Los objetivos se quedan como los pongas.')), findsOneWidget);
    expect(stepperField('Incremento (kg)'), findsNothing, reason: 'no step while the rule is off');
    expect(inSheet(find.text('Quitar de la rutina')), findsNothing);

    await tester.tap(inSheet(find.text('Regla')));
    await tester.pumpAndSettle();
    expect(find.text('Añadir tiempo'), findsNothing, reason: 'reps rules only');
    await tester.tap(find.text('Progresión doble').last);
    await tester.pumpAndSettle();
    expect(stepperText(tester, 'Incremento (kg)'), '2.5');
    expect(stepperText(tester, 'Reps desde'), '8');

    await tester.enterText(stepperField('Reps'), '12');
    await tester.pump();
    expect(stepperText(tester, 'Reps desde'), '10');
    await tester.tap(inSheet(find.text('Añadir a la rutina')));
    await tester.pumpAndSettle();
    expect(saved(results).toJson(), {
      'id': '0025',
      'sets': 3,
      'mode': 'reps',
      'reps': 12,
      'weight': 0,
      'prog': 'double',
      'repsMin': 10,
    });
    await settleAndDispose(tester, app);
  });

  testWidgets('switching to time keeps sets and weight and offers the time rules', (tester) async {
    final app = testAppState();
    final existing = RoutineExercise(id: '0001', sets: 4, mode: 'reps', reps: 15, weight: 5, prog: 'linear', inc: 2.5);
    final results = await open(tester, app, '0001', existing: existing, allowDelete: true);
    expect(inSheet(find.text('Guardar')), findsOneWidget);
    expect(inSheet(find.text('Quitar de la rutina')), findsOneWidget);

    await tester.tap(inSheet(find.text('Tiempo')));
    await tester.pump();
    expect(
      [stepperText(tester, 'Series'), stepperText(tester, 'Segundos'), stepperText(tester, 'Peso (kg)')],
      ['4', '45', '5'],
    );
    expect(inSheet(find.textContaining('Un temporizador corre')), findsOneWidget);
    // "linear" is not a time rule: it is dropped, and the inherited rule for time is off.
    expect(inSheet(find.text('Seguir la rutina (Sin progresión automática)')), findsOneWidget);
    expect(stepperField('Incremento (segundos)'), findsNothing);

    await tester.tap(inSheet(find.text('Regla')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir tiempo').last);
    await tester.pumpAndSettle();
    expect(stepperText(tester, 'Incremento (segundos)'), '5');
    await tester.tap(inSheet(find.text('Guardar')));
    await tester.pumpAndSettle();
    expect(saved(results).toJson(), {'id': '0001', 'sets': 4, 'mode': 'time', 'sec': 45, 'weight': 5, 'prog': 'time'});
    expect(existing.mode, 'reps', reason: 'the entry passed in is not modified');
    await settleAndDispose(tester, app);
  });

  testWidgets('legs step 5 kg / 10 lb by default', (tester) async {
    final app = testAppState()..updateSettings((s) => s.unit = 'lb');
    await open(tester, app, '0043');
    expect(stepperText(tester, 'Incremento (lb)'), '10');
    expect(stepperField('Peso (lb)'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('cardio has its own form without modes or rules', (tester) async {
    final app = testAppState();
    final results = await open(tester, app, '0798', existing: RoutineExercise(id: '0798', sets: 2, min: 30, speed: 10));
    expect(inSheet(find.text('Cardio')), findsOneWidget);
    expect(inSheet(find.byType(Segmented<String>)), findsNothing);
    expect(inSheet(find.text('Progresión')), findsNothing);
    expect(
      [stepperText(tester, 'Intervalos'), stepperText(tester, 'Minutos'), stepperText(tester, 'Velocidad (km/h)')],
      ['2', '30', '10'],
    );
    await tester.enterText(stepperField('Minutos'), '0');
    await tester.tap(inSheet(find.text('Guardar')));
    await tester.pumpAndSettle();
    expect(saved(results).toJson(), {'id': '0798', 'sets': 2, 'min': 20, 'speed': 10});
    await settleAndDispose(tester, app);
  });

  testWidgets('remove, and a custom exercise\'s way to its own form', (tester) async {
    final app = testAppState()
      ..updatePlan((p) => p.customEx.add(CustomExercise(id: 'cNordic', n: 'Nordic curl', bp: 'upper legs')));
    final results = await open(tester, app, 'cNordic', existing: RoutineExercise(id: 'cNordic'), allowDelete: true);
    await tester.tap(inSheet(find.text('Quitar de la rutina')));
    await tester.pumpAndSettle();
    expect(results.single, isA<ExerciseConfigRemoved>());

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Editar o eliminar este ejercicio')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Editar ejercicio propio')), findsOneWidget);
    expect(results, hasLength(1), reason: 'still waiting for the custom form');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(results.last, isNull);
    await settleAndDispose(tester, app);
  });
}
