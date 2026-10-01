import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/library/library_screen.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../widgets/test_app.dart';
import 'test_view.dart';

void main() {
  Finder chip(String label) => find.widgetWithText(AppChip, label);
  Finder exerciseRow(String name) => find.widgetWithText(ExerciseTile, name);

  /// Chip rows scroll sideways: bring the chip into view first.
  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.ensureVisible(chip(label));
    await tester.tap(chip(label));
    await tester.pump();
  }

  testWidgets('lists "Crea tu propio ejercicio", then customs, then 40 built-ins per page', (tester) async {
    useTallView(tester);
    final app = testAppState()
      ..updatePlan((p) => p.customEx.add(CustomExercise(id: 'cNordic', n: 'Nordic curl', bp: 'upper legs')));
    await pumpWithApp(tester, app, const LibraryScreen());

    expect(find.text('Ejercicios'), findsOneWidget);
    expect(find.text('1324 ejercicios con animaciones'), findsOneWidget);
    final tiles = tester.widgetList<ExerciseTile>(find.byType(ExerciseTile)).toList();
    expect(tiles, hasLength(40));
    expect(tiles.first.exercise.id, 'cNordic', reason: 'customs first');
    expect(find.text('Crea tu propio ejercicio'), findsOneWidget);

    await tester.tap(find.text('Mostrar más'));
    await tester.pump();
    expect(find.byType(ExerciseTile), findsNWidgets(80));
    await settleAndDispose(tester, app);
  });

  testWidgets('search matches English names and Spanish labels; no match says so', (tester) async {
    useTallView(tester);
    final app = testAppState();
    await pumpWithApp(tester, app, const LibraryScreen());

    await tester.enterText(find.byType(SearchField), 'barbell bench press');
    await tester.pump();
    expect(exerciseRow('Barbell Bench Press'), findsOneWidget);
    expect(find.text('Mostrar más'), findsNothing);

    await tester.enterText(find.byType(SearchField), 'pantorrillas');
    await tester.pump();
    final calves = tester.widgetList<ExerciseTile>(find.byType(ExerciseTile));
    expect(calves, isNotEmpty);
    expect(calves.every((t) => t.exercise.bodyPart == 'lower legs'), isTrue);

    await tester.enterText(find.byType(SearchField), 'zzzz nothing');
    await tester.pump();
    expect(find.byType(ExerciseTile), findsNothing);
    expect(find.text('Sin resultados'), findsOneWidget);
    expect(find.text('Crea tu propio ejercicio'), findsOneWidget, reason: 'the create row stays');
    await settleAndDispose(tester, app);
  });

  testWidgets('equipment chips follow the body part and the search, and never dead-end', (tester) async {
    useTallView(tester);
    final app = testAppState();
    await pumpWithApp(tester, app, const LibraryScreen());

    await tapChip(tester, 'Cardio');
    List<ExerciseTile> rows() => tester.widgetList<ExerciseTile>(find.byType(ExerciseTile)).toList();
    expect(rows().every((t) => t.exercise.bodyPart == 'cardio'), isTrue);
    expect(chip('Cualquier equipo'), findsOneWidget);
    expect(chip('Bici estática'), findsOneWidget);

    await tapChip(tester, 'Máquina de palanca');
    expect(rows(), hasLength(3));
    expect(rows().every((t) => t.exercise.equipment == 'leverage machine'), isTrue);

    // The search leaves no leverage machine: the equipment filter is dropped, not a dead end.
    await tester.enterText(find.byType(SearchField), 'burpee');
    await tester.pump();
    expect(rows(), isNotEmpty);
    expect(rows().every((t) => t.exercise.name.contains('burpee')), isTrue);
    expect(chip('Máquina de palanca'), findsNothing);

    // Picking a body part clears the equipment; neck has one equipment value, so no chips.
    await tester.enterText(find.byType(SearchField), '');
    await tapChip(tester, 'Cuello');
    expect(rows(), hasLength(2));
    expect(chip('Cualquier equipo'), findsNothing);

    await tapChip(tester, 'Todo');
    expect(rows(), hasLength(40));
    await settleAndDispose(tester, app);
  });

  testWidgets('"Plan" appends the default config to the chosen routine', (tester) async {
    useTallView(tester);
    final app = testAppState()
      ..updatePlan(
        (p) => p.routines.add(
          Routine(
            id: 'r1',
            name: 'Empuje',
            ex: [RoutineExercise(id: '0025')],
          ),
        ),
      );
    await pumpWithApp(tester, app, const LibraryScreen());
    await tester.enterText(find.byType(SearchField), 'barbell bench press');
    await tester.pump();

    await tester.tap(find.descendant(of: exerciseRow('Barbell Bench Press'), matching: find.text('Plan')));
    await tester.pumpAndSettle();
    expect(find.text('Añadir «Barbell Bench Press»'), findsOneWidget);
    expect(find.text('ya incluido'), findsOneWidget);

    await tester.tap(find.text('Empuje'));
    await tester.pumpAndSettle();
    final ex = app.plan.routineById('r1')!.ex;
    expect(ex, hasLength(2), reason: 'duplicates are allowed');
    expect(ex.last.toJson(), {'id': '0025', 'sets': 3, 'mode': 'reps', 'reps': 10, 'weight': 0});
    expect(find.text('«Barbell Bench Press» añadido a Empuje'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('a cardio exercise goes into a new routine with the cardio defaults', (tester) async {
    useTallView(tester);
    final app = testAppState();
    Routine? created;
    await pumpWithApp(tester, app, LibraryScreen(onRoutineCreated: (r) => created = r));
    await tester.enterText(find.byType(SearchField), 'stationary bike run');
    await tester.pump();
    final bike = tester.widget<ExerciseTile>(find.byType(ExerciseTile).first).exercise;
    expect(bike.isCardio, isTrue);

    await tester.tap(find.descendant(of: find.byType(ExerciseTile).first, matching: find.text('Plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva rutina'));
    await tester.pumpAndSettle();

    final routine = app.plan.routines.single;
    expect(routine.name, 'Nueva rutina');
    expect(routine.emoji, 'figureStrength');
    expect(routine.ex.single.toJson(), {'id': bike.id, 'sets': 1, 'min': 20, 'speed': 8});
    expect(created?.id, routine.id);
    await settleAndDispose(tester, app);
  });

  testWidgets('a routine created from the detail closes it and is reported', (tester) async {
    useTallView(tester);
    final app = testAppState();
    final created = <Routine>[];
    await pumpWithApp(tester, app, LibraryScreen(onRoutineCreated: created.add));
    await tester.enterText(find.byType(SearchField), 'barbell bench press');
    await tester.pump();

    await tester.tap(find.text('Barbell Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir a rutina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva rutina'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(created.single.ex.single.id, '0025');
    expect(app.plan.routines.single.id, created.single.id);
    await settleAndDispose(tester, app);
  });

  testWidgets('the detail sheet shows the Spanish taxonomy and toggles the instructions', (tester) async {
    useTallView(tester);
    final app = testAppState();
    await pumpWithApp(tester, app, const LibraryScreen());
    await tester.enterText(find.byType(SearchField), 'barbell bench press');
    await tester.pump();

    await tester.tap(find.text('Barbell Bench Press'));
    await tester.pumpAndSettle();
    Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
    expect(inSheet(find.text('Pecho')), findsOneWidget);
    expect(inSheet(find.text('Pectorales')), findsOneWidget);
    expect(inSheet(find.text('Barra')), findsOneWidget);
    expect(inSheet(find.text('Tríceps')), findsOneWidget);
    expect(inSheet(find.text('© Gym visual — gymvisual.com')), findsOneWidget);
    expect(find.text('Cómo hacerlo'), findsOneWidget);
    expect(find.textContaining('Túmbate'), findsOneWidget);
    expect(find.text('1RM estimado'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.textContaining('Túmbate'), findsNothing);
    expect(find.textContaining('Lie flat'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('the detail shows the best load, the last session and the 1RM from the log', (tester) async {
    useTallView(tester);
    final app = testAppState()
      ..saveWorkout(
        Workout.fromJson({
          'id': 'w1',
          'd': '2026-09-28',
          'start': 1,
          'end': 2,
          'entries': [
            {
              'id': '0025',
              'topW': null,
              'target': {'id': '0025', 'sets': 2, 'mode': 'reps', 'reps': 5},
              'sets': [
                {'w': 80, 'r': 5, 'done': true, 'rir': 2},
                {'w': 85, 'r': 3, 'done': true},
                {'w': 100, 'r': 1, 'done': false},
              ],
            },
          ],
        }),
      );
    await pumpWithApp(tester, app, const LibraryScreen());
    await tester.enterText(find.byType(SearchField), 'barbell bench press');
    await tester.pump();
    expect(find.descendant(of: exerciseRow('Barbell Bench Press'), matching: find.text('85')), findsOneWidget);

    await tester.tap(find.text('Barbell Bench Press'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Mejor: 85 kg · último 28 sept: 80×5 (RIR 2), 85×3', findRichText: true),
      findsOneWidget,
    );
    // Epley: 85 × (1 + 3/30) = 93,5 beats 80 × (1 + 5/30) = 93,3.
    expect(find.textContaining('De tu registro: 93,5 kg · 85 kg × 3 el 28 sept', findRichText: true), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('lays out at phone width, list and detail', (tester) async {
    useTallView(tester, width: 360);
    final app = testAppState();
    await pumpWithApp(tester, app, const LibraryScreen());
    await tester.enterText(find.byType(SearchField), 'bench press');
    await tester.pump();
    await tester.tap(find.text('Barbell Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('Añadir a rutina'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settleAndDispose(tester, app);
  });
}
