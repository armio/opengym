import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/plan/plan_screen.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../widgets/test_app.dart';
import '../library/test_view.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: AppButton('Abrir', onPressed: () => openRoutineEditor(context, 'r1'))),
  );
}

void main() {
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  final linkButtons = find.byTooltip('Superserie con el ejercicio de arriba');

  AppState seeded({List<RoutineExercise>? ex}) => testAppState()
    ..updatePlan((p) {
      p.routines.addAll([
        Routine(
          id: 'r1',
          name: 'Torso',
          emoji: 'arm',
          ex:
              ex ??
              [
                RoutineExercise(id: '0025', sets: 4, mode: 'reps', reps: 8, weight: 60),
                RoutineExercise(id: '0047', sets: 3, mode: 'reps', reps: 10, weight: 40),
                RoutineExercise(id: '0334', sets: 3, mode: 'reps', reps: 12, weight: 8),
              ],
        ),
        Routine(id: 'r2', name: 'Pierna', emoji: 'legs'),
      ]);
      p.week.addAll({'1': 'r1', '3': 'r2', '5': 'r1'});
    })
    ..updateSchedule((s) => s.dayPlan.addAll({'2026-10-01': 'r1', '2026-10-02': 'rest', '2026-10-03': 'r2'}));

  Future<void> openEditor(WidgetTester tester, AppState app) async {
    useTallView(tester);
    await pumpWithApp(tester, app, const _Home());
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  List<String> ids(AppState app) => [for (final e in app.plan.routineById('r1')!.ex) e.id];
  List<String?> tags(AppState app) => [for (final e in app.plan.routineById('r1')!.ex) e.sg];

  testWidgets('shows each exercise with its plan line, the coverage card and the hints', (tester) async {
    final app = seeded();
    await openEditor(tester, app);

    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('4 × 8 · 60 kg'), findsOneWidget);
    expect(find.text('Progresión lineal'), findsOneWidget, reason: 'an unset routine rule reads as linear');
    expect(find.text('Qué trabaja esta sesión'), findsOneWidget);
    expect(find.byType(BodyMap), findsOneWidget);
    expect(find.widgetWithText(MuscleChip, 'Pecho'), findsOneWidget);
    expect(find.byType(MuscleChip), findsAtLeastNWidgets(3));
    expect(linkButtons, findsNWidgets(2), reason: 'no link button on the first row');
    await settleAndDispose(tester, app);
  });

  testWidgets('the name saves on every keystroke; an empty name is stored as "Rutina"', (tester) async {
    final app = seeded();
    await openEditor(tester, app);
    final field = find.byType(TextField).first;
    expect(tester.widget<TextField>(field).controller!.text, 'Torso');

    await tester.enterText(field, '  Torso A ');
    expect(app.plan.routineById('r1')!.name, 'Torso A');
    await tester.enterText(field, '');
    await tester.pump();
    expect(app.plan.routineById('r1')!.name, 'Rutina');
    expect(tester.widget<TextField>(field).controller!.text, '', reason: 'the field is not rewritten');
    await settleAndDispose(tester, app);
  });

  testWidgets('icon and routine progression', (tester) async {
    final app = seeded();
    await openEditor(tester, app);

    await tester.tap(find.byTooltip('Elige un icono'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Recuperación')), findsOneWidget);
    await tester.tap(inSheet(find.byWidgetPredicate((w) => w is AppIcon && w.name == 'heart')));
    await tester.pumpAndSettle();
    expect(app.plan.routineById('r1')!.emoji, 'heart');

    await tester.tap(find.text('Progresión'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Añadir tiempo')), findsNothing, reason: 'reps policies only');
    await tester.tap(inSheet(find.text('Progresión doble')));
    await tester.pumpAndSettle();
    expect(app.plan.routineById('r1')!.prog, 'double');
    expect(find.text('Progresión doble'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('reorder with the arrows; the ends do nothing', (tester) async {
    final app = seeded();
    await openEditor(tester, app);

    await tester.tap(find.byTooltip('Subir').first);
    await tester.pump();
    expect(ids(app), ['0025', '0047', '0334']);
    await tester.tap(find.byTooltip('Bajar').first);
    await tester.pump();
    expect(ids(app), ['0047', '0025', '0334']);
    await tester.tap(find.byTooltip('Bajar').last);
    await tester.pump();
    expect(ids(app), ['0047', '0025', '0334']);
    await tester.tap(find.byTooltip('Subir').last);
    await tester.pump();
    expect(ids(app), ['0047', '0334', '0025']);
    await settleAndDispose(tester, app);
  });

  testWidgets('superset links: link, extend, unlink the middle, move out of a pair', (tester) async {
    final app = seeded();
    await openEditor(tester, app);
    expect(find.text('Superserie'), findsNothing);

    await tester.tap(linkButtons.at(0));
    await tester.pump();
    final first = tags(app)[0];
    expect(first, startsWith('sg'));
    expect(tags(app), [first, first, null]);
    expect(find.text('Superserie'), findsOneWidget);

    await tester.tap(linkButtons.at(1));
    await tester.pump();
    expect(tags(app), [first, first, first], reason: 'joins the group above');
    expect(find.text('Superserie'), findsOneWidget, reason: 'one label per group');

    await tester.tap(linkButtons.at(0));
    await tester.pump();
    expect(tags(app), [null, null, null], reason: 'unlinking the middle dissolves the chain');
    expect(find.text('Superserie'), findsNothing);

    await tester.tap(linkButtons.at(0));
    await tester.pump();
    final second = tags(app)[0];
    expect(second, isNot(first), reason: 'every link gets a fresh tag');
    await tester.tap(find.byTooltip('Bajar').at(1));
    await tester.pump();
    expect(ids(app), ['0025', '0334', '0047']);
    expect(tags(app), [null, null, null], reason: 'a partnerless tag is dropped');
    await settleAndDispose(tester, app);
  });

  testWidgets('the config sheet edits an entry keeping its superset, or removes it', (tester) async {
    final app = seeded();
    await openEditor(tester, app);
    await tester.tap(linkButtons.at(0));
    await tester.pump();
    final tag = tags(app)[0];

    await tester.tap(find.text('Barbell Bench Press'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Guardar')), findsOneWidget);
    final sets = inSheet(
      find.descendant(of: find.widgetWithText(ValueStepper, 'Series'), matching: find.byType(TextField)),
    );
    await tester.enterText(sets, '5');
    await tester.tap(inSheet(find.text('Tiempo')));
    await tester.pump();
    await tester.tap(inSheet(find.text('Guardar')));
    await tester.pumpAndSettle();
    expect(app.plan.routineById('r1')!.ex.first.toJson(), {
      'id': '0025',
      'sets': 5,
      'mode': 'time',
      'sec': 45,
      'weight': 60,
      'sg': tag,
    });
    expect(find.text('5 × 0:45 · 60 kg'), findsOneWidget);

    await tester.tap(find.text('Barbell Incline Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Quitar de la rutina')));
    await tester.pumpAndSettle();
    expect(ids(app), ['0025', '0334']);
    expect(tags(app), [null, null], reason: 'its partner is left alone');
    await settleAndDispose(tester, app);
  });

  testWidgets('an unknown exercise stays visible and removable', (tester) async {
    final app = seeded(ex: [RoutineExercise(id: 'gone', sets: 2, reps: 8)]);
    await openEditor(tester, app);
    expect(find.text('Ejercicio Desconocido'), findsOneWidget);
    await tester.tap(find.text('Ejercicio Desconocido'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.text('Quitar de la rutina')));
    await tester.pumpAndSettle();
    expect(ids(app), isEmpty);
    expect(find.text('Aún no hay ejercicios — añade el primero.'), findsOneWidget);
    expect(find.text('Qué trabaja esta sesión'), findsNothing);
    await settleAndDispose(tester, app);
  });

  testWidgets('add exercises: pick, configure, add — the picker stays open for the next one', (tester) async {
    final app = seeded(ex: []);
    await openEditor(tester, app);

    await tester.tap(find.widgetWithText(AppButton, 'Añadir ejercicio'));
    await tester.pumpAndSettle();
    await tester.enterText(inSheet(find.byType(SearchField)), 'barbell full squat');
    await tester.pump();
    await tester.tap(inSheet(find.text('Barbell Full Squat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir a la rutina'));
    await tester.pumpAndSettle();
    expect(app.plan.routineById('r1')!.ex.single.toJson(), {
      'id': '0043',
      'sets': 3,
      'mode': 'reps',
      'reps': 10,
      'weight': 0,
    });
    expect(inSheet(find.byType(SearchField)), findsOneWidget, reason: 'still in the picker');

    await tester.enterText(inSheet(find.byType(SearchField)), 'stationary bike walk');
    await tester.pump();
    await tester.tap(inSheet(find.text('Stationary Bike Walk')));
    await tester.pumpAndSettle();
    expect(find.text('Intervalos'), findsOneWidget, reason: 'cardio form');
    await tester.tap(find.text('Añadir a la rutina'));
    await tester.pumpAndSettle();
    expect(app.plan.routineById('r1')!.ex.last.toJson(), {'id': '0798', 'sets': 1, 'min': 20, 'speed': 8});

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Stationary Bike Walk'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('deleting the routine asks first, then clears the week and the reschedules', (tester) async {
    final app = seeded();
    await openEditor(tester, app);

    await tester.tap(find.text('Eliminar rutina'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar rutina?'), findsOneWidget);
    expect(find.text('«Torso» y sus ejercicios se eliminarán.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(app.plan.routineById('r1'), isNotNull);

    await tester.tap(find.text('Eliminar rutina'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(app.plan.routineById('r1'), isNull);
    expect(app.plan.week, {'3': 'r2'});
    expect(app.schedule.dayPlan, {'2026-10-02': 'rest', '2026-10-03': 'r2'});
    expect(find.byType(RoutineEditorScreen), findsNothing);
    expect(find.text('Abrir'), findsOneWidget);
    await settleAndDispose(tester, app);
  });

  testWidgets('the editor leaves when its routine disappears (e.g. deleted on another device)', (tester) async {
    final app = seeded();
    await openEditor(tester, app);
    app.deleteRoutine('r1');
    await tester.pumpAndSettle();
    expect(find.byType(RoutineEditorScreen), findsNothing);
    await settleAndDispose(tester, app);
  });
}
