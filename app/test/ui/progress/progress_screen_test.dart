import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/ui/screens/progress/progress_screen.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../widgets/test_app.dart';
import '../library/test_view.dart';
import 'progress_fixtures.dart';

void main() {
  Finder chip(String label) => find.widgetWithText(AppChip, label);
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

  Future<void> open(WidgetTester tester, String section) async {
    await tester.ensureVisible(chip(section));
    await tester.pumpAndSettle();
    await tester.tap(chip(section));
    await tester.pumpAndSettle();
  }

  testWidgets('the effort section exists only once some set carries a rating', (tester) async {
    useTallView(tester, width: 390);
    final plain = seededProgressApp(effort: false);
    await pumpWithApp(tester, plain, const ProgressScreen());
    expect(chip('Resumen'), findsOneWidget);
    expect(chip('Músculos'), findsOneWidget);
    expect(chip('Esfuerzo'), findsNothing);
    await settleAndDispose(tester, plain);

    final rated = seededProgressApp();
    await pumpWithApp(tester, rated, const ProgressScreen());
    await open(tester, 'Esfuerzo');
    expect(find.text('esfuerzo medio'), findsOneWidget);
    expect(find.text('Dónde caen las series'), findsOneWidget);
    expect(find.text('RIR 4+'), findsOneWidget);
    expect(find.text('a RIR 3 o más duro'), findsOneWidget);
    expect(find.textContaining('series completadas valoradas'), findsOneWidget);
    await settleAndDispose(tester, rated);
  });

  testWidgets('the summary shows the tiles, the weekly bars and the recent workouts', (tester) async {
    useTallView(tester, width: 390);
    mockPathProvider(tester);
    final app = seededProgressApp();
    await pumpWithApp(tester, app, const ProgressScreen());
    final total = app.workouts.length;
    expect(find.widgetWithText(StatTile, '$total'), findsOneWidget);
    expect(find.text('Racha semanal'), findsOneWidget);
    expect(find.text('Volumen total'), findsOneWidget);
    expect(find.textContaining('Entrenos por semana'), findsOneWidget);
    expect(find.textContaining('tu plan: 3 días'), findsOneWidget);
    expect(find.byType(WorkoutRow), findsNWidgets(6));

    await tester.tap(find.text('Todos $total'));
    await tester.pumpAndSettle();
    expect(find.text('Historial'), findsOneWidget);
    expect(find.text('Septiembre 2026'), findsOneWidget);
    expect(find.text('Junio 2026'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('every section has an empty state', (tester) async {
    useTallView(tester, width: 390);
    final app = testAppState();
    await pumpWithApp(tester, app, const ProgressScreen());
    expect(find.text('Termina tu primer entrenamiento para ver tu progreso aquí.'), findsOneWidget);
    expect(find.widgetWithText(StatTile, '—'), findsOneWidget, reason: 'no weight change without weigh-ins');

    await open(tester, 'Peso corporal');
    expect(find.text('Aún sin datos'), findsOneWidget);
    expect(find.text('Aún no hay pesajes. Registra tu peso para ver tu curva.'), findsOneWidget);

    await open(tester, 'Actividad');
    expect(find.text('Aún no hay entrenamientos en los últimos 12 meses.'), findsOneWidget);

    await open(tester, 'Ejercicios');
    expect(find.text('Termina tu primer entrenamiento para ver curvas de progreso aquí.'), findsOneWidget);

    await open(tester, 'Músculos');
    expect(find.textContaining('Termina tu primer entrenamiento para ver qué músculos'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('a weigh-in can be corrected or deleted from the log', (tester) async {
    useTallView(tester, width: 390);
    final app = seededProgressApp(weeks: 1);
    await pumpWithApp(tester, app, const ProgressScreen(initialSection: ProgressSection.bodyWeight));
    final latest = app.lastBodyWeight!;
    expect(find.text('Pesajes'), findsOneWidget);
    expect(find.text('Mostrar más'), findsOneWidget, reason: 'the log pages by ten');

    await tester.tap(find.text('mié, 30 sept'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Editar pesaje')), findsOneWidget);
    await tester.tap(inSheet(find.text('+1')));
    await tester.pump();
    await tester.tap(inSheet(find.text('Guardar')));
    await tester.pumpAndSettle();
    expect(app.lastBodyWeight!.w, latest.w + 1);
    expect(app.lastBodyWeight!.t, latest.t, reason: 'the entry keeps its time');
    expect(app.bodyWeights, hasLength(40));

    await tester.tap(find.text('mié, 30 sept'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Borrar pesaje')));
    await tester.pumpAndSettle();
    expect(app.bodyWeights, hasLength(39));
    expect(app.lastBodyWeight!.d, '2026-09-27');
    await settleAndDispose(tester, app);
  });

  testWidgets('exercise progress switches exercise and metric, with records and the 1RM calculator', (tester) async {
    useTallView(tester, width: 390);
    final app = seededProgressApp();
    await pumpWithApp(tester, app, const ProgressScreen(initialSection: ProgressSection.exercises));
    // Alphabetical: barbell bench press first.
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('Mejor serie'), findsOneWidget);
    expect(find.text('1RM est.'), findsOneWidget);
    expect(find.text('Mejor peso por entrenamiento · Mejor: 97,5 kg'), findsOneWidget);
    expect(find.text('Mejor carga'), findsOneWidget);
    expect(find.byType(TrendChart), findsOneWidget);

    await tester.tap(find.text('1RM est.'));
    await tester.pumpAndSettle();
    expect(find.text('1RM estimado por entrenamiento · Mejor: 123,5 kg'), findsOneWidget);
    expect(find.textContaining('Mejor estimación a partir de 97,5 kg × 8'), findsOneWidget);

    // The calculator: Epley up to 12 reps.
    final steppers = find.byType(ValueStepper);
    await tester.enterText(find.descendant(of: steppers.first, matching: find.byType(TextField)), '100');
    await tester.enterText(find.descendant(of: steppers.last, matching: find.byType(TextField)), '5');
    await tester.pump();
    expect(find.text('116,7 kg'), findsOneWidget);
    await tester.enterText(find.descendant(of: steppers.last, matching: find.byType(TextField)), '13');
    await tester.pump();
    expect(find.textContaining('de 1 a 12 repeticiones'), findsOneWidget);

    // A timed exercise: longest hold, no calculator.
    await tester.tap(find.text('Ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Weighted Front Plank')));
    await tester.pumpAndSettle();
    expect(find.text('Isométrico más largo'), findsOneWidget);
    expect(find.textContaining('Isométrico más largo por entrenamiento'), findsOneWidget);
    expect(find.text('Calculadora de 1RM'), findsNothing);
    expect(find.text('1RM est.'), findsNothing);
    await settleAndDispose(tester, app);
  });

  testWidgets('muscle balance offers the hard-set view when the window holds hard sets', (tester) async {
    useTallView(tester, width: 390);
    final app = seededProgressApp();
    await pumpWithApp(tester, app, const ProgressScreen(initialSection: ProgressSection.muscles));
    expect(find.byType(BodyMap), findsOneWidget);
    expect(find.textContaining('por series trabajadas'), findsOneWidget);
    expect(find.text('Sin entrenar en este periodo'), findsOneWidget);

    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('por series duras'), findsOneWidget);
    expect(find.text('Duras'), findsOneWidget);

    await tester.tap(find.text('Todo').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('por series duras'), findsOneWidget, reason: 'the whole history still has hard sets');
    await settleAndDispose(tester, app);
  });
}
