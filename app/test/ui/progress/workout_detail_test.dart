import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/ui/screens/progress/progress_screen.dart';

import '../../widgets/test_app.dart';
import '../library/test_view.dart';
import 'progress_fixtures.dart';

void main() {
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

  testWidgets('the detail shows every entry with its sets, effort, target and PR', (tester) async {
    useTallView(tester, width: 390);
    mockPathProvider(tester);
    final app = testAppState()
      ..saveWorkout(
        progressWorkout(
          'w1',
          '2026-09-28',
          name: 'Empuje',
          minutes: 52,
          prs: ['0025'],
          entries: [repsEntry('0025', 60, sets: 2, rir: 2), timeEntry('2135', 45, sets: 1)],
        )..bw = 78.5,
      );
    await pumpWithApp(tester, app, const HistoryScreen());
    expect(find.text('Septiembre 2026'), findsOneWidget);
    expect(find.text('1 entrenamiento'), findsWidgets);

    await tester.tap(find.text('Empuje'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('lun, 28 sept · 52 min · 960 kg · 78,5 kg')), findsOneWidget);
    expect(inSheet(find.text('Barbell Bench Press')), findsOneWidget);
    expect(inSheet(find.text('PR')), findsOneWidget);
    expect(inSheet(find.text('60×8 (RIR 2)  ·  60×8 (RIR 2)')), findsOneWidget);
    expect(inSheet(find.text('Objetivo: 2 × 8 · 60 kg')), findsOneWidget);
    expect(inSheet(find.text('Weighted Front Plank')), findsOneWidget);
    expect(inSheet(find.text('0:45')), findsOneWidget);
    expect(inSheet(find.text('Objetivo: 1 × 0:45')), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('rating and note are edited in place', (tester) async {
    useTallView(tester, width: 390);
    mockPathProvider(tester);
    final app = testAppState()..saveWorkout(progressWorkout('w1', '2026-09-28', name: 'Empuje'));
    await pumpWithApp(tester, app, const HistoryScreen());
    await tester.tap(find.text('Empuje'));
    await tester.pumpAndSettle();

    await tester.tap(inSheet(find.text('Brutal')));
    await tester.pump();
    expect(app.workoutById('w1')!.rating, 'hard');
    await tester.tap(inSheet(find.text('Bien')));
    await tester.pump();
    expect(app.workoutById('w1')!.rating, 'right');
    await tester.tap(inSheet(find.text('Bien')));
    await tester.pump();
    expect(app.workoutById('w1')!.rating, isNull, reason: 'tapping the current rating clears it');
    expect(app.workoutById('w1')!.toJson().containsKey('rating'), isFalse);

    await tester.enterText(inSheet(find.byType(TextField)), '  La última serie costó.  ');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(app.workoutById('w1')!.note, 'La última serie costó.');

    await tester.enterText(inSheet(find.byType(TextField)), '   ');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(app.workoutById('w1')!.toJson().containsKey('note'), isFalse, reason: 'an empty note deletes the key');

    await tester.enterText(inSheet(find.byType(TextField)), 'x' * 400);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(app.workoutById('w1')!.note, hasLength(300));
    await settleAndDispose(tester, app);
  });

  testWidgets('deleting asks first and leaves working weights and other PRs alone', (tester) async {
    useTallView(tester, width: 390);
    mockPathProvider(tester);
    final app = testAppState()
      ..saveWorkout(progressWorkout('old', '2026-09-21', name: 'Pierna', prs: ['0043']))
      ..saveWorkout(progressWorkout('new', '2026-09-28', name: 'Empuje', entries: [repsEntry('0025', 100)]))
      ..setExWeight('0025', 100);
    await pumpWithApp(tester, app, const HistoryScreen());
    expect(find.text('2 entrenamientos'), findsWidgets);

    await tester.tap(find.text('Empuje'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Eliminar entrenamiento')));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar entrenamiento?'), findsOneWidget);
    expect(find.text('Se elimina de tu historial para siempre.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(app.workoutById('new'), isNotNull);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'cancelling keeps the sheet open');

    await tester.tap(inSheet(find.text('Eliminar entrenamiento')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pump();
    expect(app.workoutById('new'), isNull);
    expect(find.text('Entrenamiento eliminado'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Empuje'), findsNothing);
    expect(find.text('1 entrenamiento'), findsWidgets);
    expect(app.exWeights['0025']!.w, 100, reason: 'no working-weight recompute (data-B10)');
    expect(app.workoutById('old')!.prs, ['0043']);
    await settleAndDispose(tester, app);
  });

  testWidgets('an empty history says so', (tester) async {
    final app = testAppState();
    await pumpWithApp(tester, app, const HistoryScreen());
    expect(find.text('Aún no hay entrenamientos.'), findsOneWidget);
    expect(find.text('0 entrenamientos'), findsOneWidget);
    await settleAndDispose(tester, app);
  });
}
