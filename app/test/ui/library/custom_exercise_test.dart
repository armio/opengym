import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/library/library_screen.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../widgets/test_app.dart';
import 'test_view.dart';

void main() {
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  final nameField = inSheet(find.byType(TextField)).first;
  final descriptionField = inSheet(find.byType(TextField)).last;

  testWidgets('creates a custom exercise from the search text, validating the form', (tester) async {
    useTallView(tester);
    final app = testAppState();
    await pumpWithApp(tester, app, const LibraryScreen());
    await tester.enterText(find.byType(SearchField), 'Nordic curl');
    await tester.pump();

    await tester.tap(find.text('Crea tu propio ejercicio'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Crea tu propio ejercicio')), findsOneWidget);
    expect(tester.widget<TextField>(nameField).controller!.text, 'Nordic curl', reason: 'prefilled with the query');

    await tester.tap(find.text('Crear ejercicio'));
    await tester.pump();
    expect(find.text('Elige una parte del cuerpo'), findsOneWidget);

    await tester.enterText(nameField, '  BARBELL bench press ');
    await tester.tap(inSheet(find.widgetWithText(AppChip, 'Piernas')));
    await tester.tap(find.text('Crear ejercicio'));
    await tester.pump();
    expect(find.text('«Barbell Bench Press» ya existe'), findsOneWidget);

    await tester.enterText(nameField, '  Nordic curl ');
    await tester.enterText(descriptionField, ' De rodillas, baja despacio ');
    await tester.tap(find.text('Crear ejercicio'));
    await tester.pumpAndSettle();

    final custom = app.plan.customEx.single;
    expect(custom.id, startsWith('c'));
    expect(custom.toJson(), {
      'id': custom.id,
      'n': 'Nordic curl',
      'bp': 'upper legs',
      'desc': 'De rodillas, baja despacio',
      'tg': '',
      'eq': 'custom',
      'custom': true,
    });
    // The new exercise's detail opens, without the animation or the 1RM hidden.
    expect(inSheet(find.text('Nordic Curl')), findsOneWidget);
    expect(inSheet(find.text('De rodillas, baja despacio')), findsOneWidget);
    expect(inSheet(find.text('Propio')), findsOneWidget);
    expect(inSheet(find.text('Editar')), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('edits a custom exercise from its detail sheet', (tester) async {
    useTallView(tester);
    final app = testAppState()
      ..updatePlan((p) => p.customEx.add(CustomExercise(id: 'cNordic', n: 'Nordic curl', bp: 'upper legs')));
    await pumpWithApp(tester, app, const LibraryScreen());

    await tester.tap(find.text('Nordic Curl'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Editar')));
    await tester.pumpAndSettle();
    expect(find.text('Editar ejercicio propio'), findsOneWidget);

    await tester.enterText(nameField, 'Nordic hamstring curl');
    await tester.tap(inSheet(find.widgetWithText(AppChip, 'Cardio')));
    await tester.pump();
    expect(find.textContaining('registran tiempo + velocidad'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final custom = app.plan.customById('cNordic')!;
    expect(custom.n, 'Nordic hamstring curl');
    expect(custom.bp, 'cardio');
    expect(find.text('Guardado'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('deleting a custom exercise confirms, then cascades through AppState', (tester) async {
    useTallView(tester);
    final app = testAppState()
      ..updatePlan((p) {
        p.customEx.add(CustomExercise(id: 'cNordic', n: 'Nordic curl', bp: 'upper legs'));
        p.routines.add(
          Routine(
            id: 'r1',
            name: 'Pierna',
            ex: [
              RoutineExercise(id: '0043', sg: 'sg1'),
              RoutineExercise(id: 'cNordic', sg: 'sg1'),
            ],
          ),
        );
      })
      ..setExWeight('cNordic', 10)
      ..saveWorkout(
        Workout.fromJson({
          'id': 'w1',
          'd': '2026-09-28',
          'start': 1,
          'end': 2,
          'entries': [
            {
              'id': 'cNordic',
              'topW': null,
              'sets': [
                {'w': 0, 'r': 8, 'done': true},
              ],
            },
          ],
        }),
      );
    await pumpWithApp(tester, app, const LibraryScreen());

    await tester.tap(find.text('Nordic Curl'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Eliminar')));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar «Nordic Curl»?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Eliminar')));
    await tester.pumpAndSettle();

    expect(app.plan.customEx, isEmpty);
    expect(app.plan.routineById('r1')!.ex.single.toJson(), {'id': '0043', 'sets': 3}, reason: 'orphan sg cleaned');
    expect(app.exWeights, isNot(contains('cNordic')));
    expect(app.workoutById('w1')!.entries.single.n, 'Nordic curl');
    expect(find.byType(BottomSheet), findsNothing, reason: 'the detail closes');
    expect(find.text('Ejercicio eliminado'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('a custom exercise in the workout in progress cannot be deleted', (tester) async {
    useTallView(tester);
    final app = testAppState()
      ..updatePlan((p) => p.customEx.add(CustomExercise(id: 'cNordic', n: 'Nordic curl', bp: 'upper legs')));
    await app.startActive(
      ActiveWorkout.fromJson({
        'id': 'a1',
        'd': '2026-09-30',
        'start': 1,
        'name': 'Libre',
        'entries': [
          {'id': 'cNordic', 'sets': <Object>[]},
        ],
      }),
    );
    await pumpWithApp(tester, app, const LibraryScreen());

    await tester.tap(find.text('Nordic Curl'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Eliminar')));
    await tester.pumpAndSettle();
    expect(find.text('Termina primero tu entrenamiento actual'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(app.plan.customEx, hasLength(1));
    await app.discardActive();
    await settleAndDispose(tester, app);
  });
}
