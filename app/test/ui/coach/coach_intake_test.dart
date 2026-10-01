import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/ui/screens/coach/intake_screen.dart';
import 'package:opengym/ui/widgets/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coach_harness.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

AppChip chip(WidgetTester tester, String label) => tester.widget<AppChip>(find.widgetWithText(AppChip, label));

Segmented<int> segmented(WidgetTester tester) => tester.widget<Segmented<int>>(find.byType(Segmented<int>));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the six steps save the profile as the owner\'s explicit save', (tester) async {
    final h = CoachHarness();
    await h.sync();
    await pumpCoach(tester, h);
    await tapText(tester, 'Tus respuestas');

    expect(find.byType(AthleteIntakeScreen), findsOneWidget);
    expect(find.text('Paso 1 de 6'), findsOneWidget);
    expect(find.text('Elige un objetivo y tu punto de partida para continuar.'), findsOneWidget);
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'Siguiente')).onPressed, isNull);
    await tapText(tester, 'Ganar fuerza');
    await tapText(tester, 'Entreno con regularidad');
    await tapText(tester, 'Siguiente');

    expect(find.text('Paso 2 de 6'), findsOneWidget);
    expect([for (final s in segmented(tester).segments) s.value], [2, 3, 4, 5, 6]);
    await tapText(tester, '4');
    await tapText(tester, 'Ma');
    await tapText(tester, 'Siguiente');

    expect(find.text('Paso 3 de 6'), findsOneWidget);
    await tapText(tester, '60 min');
    await tapText(tester, 'Siguiente');

    expect(find.text('Paso 4 de 6'), findsOneWidget);
    final labels = tester.widgetList<AppChip>(find.byType(AppChip)).map((c) => c.label).toList();
    expect(labels, hasLength(14));
    expect(labels.take(4), ['peso corporal', 'mancuerna', 'polea', 'barra'], reason: 'shown capitalised');
    await tapText(tester, 'Mancuerna');
    await tapText(tester, 'Barra');
    await tapText(tester, 'Siguiente');

    expect(find.text('Paso 5 de 6'), findsOneWidget);
    expect(find.textContaining('Si algo duele de verdad, consulta a un profesional'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Rodilla izquierda delicada');
    await tapText(tester, 'Siguiente');

    expect(find.text('Paso 6 de 6'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Peso muerto');
    await tester.enterText(find.byType(TextField).at(2), 'Quiero llegar a 100 kg en sentadilla');
    await tapText(tester, 'Guardar');

    final a = h.app.athlete;
    expect(a.goal, 'strength');
    expect(a.experience, 'regular');
    expect(a.daysPerWeek, 4);
    expect(a.preferredDays, [1, 2, 3, 5]);
    expect(a.sessionMin, 60);
    expect(a.equipment, ['dumbbell', 'barbell']);
    expect(a.limitations, 'Rodilla izquierda delicada');
    expect((a.likes, a.dislikes, a.notes), ('Peso muerto', '', 'Quiero llegar a 100 kg en sentadilla'));
    expect(a.savedAt, h.clock.nowMs());
    expect(a.updatedBy, 'app');
    expect(find.text('Guardado'), findsOneWidget);
    expect(find.byType(AthleteIntakeScreen), findsNothing);
    expect(find.textContaining('Ganar fuerza · 4 días a la semana · 60 min'), findsOneWidget);

    // Saved explicitly, the profile now syncs.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final stored = h.server.docs['athlete']!['data'] as Map;
    expect(stored['updatedBy'], 'app');
    expect(stored['savedAt'], h.clock.nowMs());
    await disposeHarness(tester, h);
  });

  testWidgets('values outside the options (set by Claude) show as an extra selected choice', (tester) async {
    final h = CoachHarness();
    h.server.putDoc('athlete', {
      'goal': 'muscle',
      'experience': 'returning',
      'daysPerWeek': 7,
      'preferredDays': [1, 3, 5],
      'sessionMin': 120,
      'equipment': ['dumbbell', 'rope'],
      'limitations': '',
      'likes': '',
      'dislikes': '',
      'notes': '',
      'savedAt': createdAt,
      'updatedBy': 'claude',
    });
    await h.sync();
    await pumpCoach(tester, h);
    await tapText(tester, 'Ver perfil');
    expect(find.text('Claude actualizó tu perfil'), findsNothing, reason: 'opening the profile marks it seen');

    await tapText(tester, 'Siguiente');
    expect([for (final s in segmented(tester).segments) s.value], [2, 3, 4, 5, 6, 7]);
    expect(segmented(tester).value, 7);
    await tapText(tester, 'Siguiente');
    expect([for (final s in segmented(tester).segments) s.value], [30, 45, 60, 75, 90, 120]);
    expect(segmented(tester).value, 120);
    await tapText(tester, 'Siguiente');
    expect(find.byType(AppChip), findsNWidgets(15));
    expect(chip(tester, 'Cuerda').selected, isTrue);
    expect(chip(tester, 'Mancuerna').selected, isTrue);

    // "Guardar" in the header saves from any step, keeping the extra values.
    await tapText(tester, 'Guardar');
    final a = h.app.athlete;
    expect((a.daysPerWeek, a.sessionMin), (7, 120));
    expect(a.equipment, ['dumbbell', 'rope']);
    expect(a.updatedBy, 'app');
    expect(a.savedAt, h.clock.nowMs());
    await disposeHarness(tester, h);
  });

  testWidgets('back walks the steps before leaving', (tester) async {
    final h = CoachHarness();
    await h.sync();
    await pumpCoach(tester, h);
    await tapText(tester, 'Tus respuestas');
    await tapText(tester, 'Ganar músculo');
    await tapText(tester, 'Empiezo con las pesas');
    await tapText(tester, 'Siguiente');
    await tapText(tester, 'Siguiente');
    expect(find.text('Paso 3 de 6'), findsOneWidget);

    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();
    expect(find.text('Paso 2 de 6'), findsOneWidget);
    await tapText(tester, 'Atrás');
    expect(find.text('Paso 1 de 6'), findsOneWidget);
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();

    expect(find.byType(AthleteIntakeScreen), findsNothing);
    expect(h.app.athlete.savedAt, isNull, reason: 'leaving without saving keeps nothing');
    expect(h.app.athlete.goal, isNull);
    await disposeHarness(tester, h);
  });
}
