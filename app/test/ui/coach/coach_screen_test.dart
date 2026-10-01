import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/widgets/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coach_harness.dart';

const day = 86400000;

/// The plan after Claude's `p0` raised the bench press to 4 sets.
JsonMap appliedPlan() {
  final plan = planJson();
  ((plan['routines'] as List)[0]['ex'] as List)[0]['sets'] = 4;
  return plan;
}

/// A coach doc with a create, a review (one decision of each kind) and a snapshot for `p0`.
JsonMap coachWithHistory() => {
  'log': [
    {'id': 'l1', 'kind': 'create', 'at': createdAt - 20 * day, 'proposalId': 'pOld', 'summary': '', 'routines': 3},
    {
      'id': 'l2',
      'kind': 'review',
      'at': createdAt - 5 * day,
      'proposalId': 'p0',
      'summary': 'Tu press de banca se estancó: una serie más.',
      'evidence': {'from': '2026-08-01', 'to': '2026-09-15', 'sessions': 14},
      'notes': ['Duerme más de 7 horas si puedes.'],
      'decisions': [
        {
          'id': 'c1',
          'type': 'sets',
          'target': {'routineId': 'r1', 'exId': '0025'},
          'before': 3,
          'after': 4,
          'why': 'Tres sesiones fallando la última serie.',
          'status': 'accepted',
        },
        {'id': 'c2', 'type': 'reps', 'why': 'Rango más amplio.', 'status': 'rejected'},
        {'id': 'c3', 'type': 'week', 'why': 'Mover el viernes.', 'status': 'stale'},
      ],
    },
  ],
  'snapshots': [
    {
      'at': createdAt - 5 * day,
      'proposalId': 'p0',
      'label': 'Antes de los cambios del Coach',
      'routines': planJson()['routines'],
      'week': planJson()['week'],
    },
  ],
  'lastReview': {'at': createdAt - 5 * day},
};

/// A harness whose server holds an applied change set `p0` and its history.
Future<CoachHarness> withHistory() async {
  final h = CoachHarness();
  h.server
    ..putDoc('plan', appliedPlan())
    ..putDoc('coach', coachWithHistory());
  h.addProposal({
    'id': 'p0',
    'kind': 'changes',
    'status': 'applied',
    'changes': [
      {
        'id': 'c2',
        'type': 'reps',
        'target': {'routineId': 'r1', 'exId': '0025'},
        'before': 10,
        'after': 12,
        'why': 'Rango más amplio.',
      },
    ],
  });
  await h.sync();
  return h;
}

JsonMap athleteBy(String who, int savedAt) => {
  'goal': 'muscle',
  'experience': 'returning',
  'daysPerWeek': 4,
  'preferredDays': [1, 2, 4, 5],
  'sessionMin': 60,
  'equipment': <String>[],
  'limitations': '',
  'likes': '',
  'dislikes': '',
  'notes': '',
  'savedAt': savedAt,
  'updatedBy': who,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('with nothing pending: an empty state, how to connect Claude and an unset profile', (tester) async {
    final h = CoachHarness();
    await h.sync();
    await pumpCoach(tester, h);

    expect(find.textContaining('No hay propuestas pendientes.'), findsOneWidget);
    expect(find.textContaining('sus propuestas llegarán aquí'), findsOneWidget);
    expect(find.text('Conectar Claude'), findsOneWidget);
    expect(find.text('Sin configurar'), findsOneWidget);
    expect(find.text('Historial del Coach'), findsNothing);
    expect(find.text('Deshacer los últimos cambios del Coach'), findsNothing);
    await disposeHarness(tester, h);
  });

  testWidgets('"Conectar Claude" shows the connector URL, the steps and prompts to copy', (tester) async {
    final copied = captureClipboard(tester);
    final h = CoachHarness();
    await h.sync();
    await pumpCoach(tester, h);

    expect(find.text('https://gym.example.com/mcp'), findsOneWidget);
    expect(find.textContaining('Añadir conector personalizado'), findsOneWidget);
    expect(find.text('Claude Desktop'), findsOneWidget);

    await tester.tap(find.byTooltip('Copiar'));
    await tester.pump();
    expect(copied(), 'https://gym.example.com/mcp');

    await tester.tap(find.byTooltip('Copiar comando'));
    await tester.pump();
    expect(copied(), 'claude mcp add --transport http opengym https://gym.example.com/mcp');

    expect(find.byTooltip('Copiar petición'), findsAtLeastNWidgets(4));
    await tester.tap(find.byTooltip('Copiar petición').first);
    await tester.pump();
    expect(copied(), 'Diseña mi plan de entrenamiento con openGym');
    await disposeHarness(tester, h);
  });

  testWidgets('history: newest first, with a detail sheet per entry', (tester) async {
    final h = await withHistory();
    await pumpCoach(tester, h);

    final titles = tester.widgetList<ListItem>(find.byType(ListItem)).map((i) => i.title).toList();
    expect(titles, ['Revisó tu entrenamiento', 'Creó un plan']);
    expect(find.text('16 sept · 1 aplicado'), findsOneWidget);

    await tester.tap(find.text('Revisó tu entrenamiento'));
    await tester.pumpAndSettle();
    expect(find.text('Revisión del Coach'), findsOneWidget);
    expect(find.text('Tu press de banca se estancó: una serie más.'), findsOneWidget);
    expect(find.text('Basado en 14 sesiones · 1 ago – 15 sept'), findsOneWidget);
    expect(find.text('Barbell Bench Press: series'), findsOneWidget);
    // Declined decisions carry no target: the proposal on this device fills in the exercise.
    expect(find.text('Barbell Bench Press: repeticiones'), findsOneWidget);
    expect(find.text('Cambiar lo planificado en un día'), findsOneWidget);
    expect(find.text('aplicado'), findsOneWidget);
    expect(find.text('rechazado'), findsOneWidget);
    expect(find.text('no aplicable'), findsOneWidget);
    expect(find.text('Duerme más de 7 horas si puedes.'), findsOneWidget);
    await disposeHarness(tester, h);
  });

  testWidgets('history lists at most the last 20 entries', (tester) async {
    final h = CoachHarness();
    h.server.putDoc('coach', {
      'log': [
        for (var i = 0; i < 25; i++) {'id': 'l$i', 'kind': 'create', 'at': createdAt + i * day, 'summary': ''},
      ],
      'snapshots': <dynamic>[],
      'lastReview': null,
    });
    await h.sync();
    await pumpCoach(tester, h);
    expect(find.text('Creó un plan'), findsNWidgets(20));
    expect(find.text('15 oct'), findsOneWidget, reason: 'the newest entry');
    await disposeHarness(tester, h);
  });

  testWidgets('"Deshacer los últimos cambios del Coach" restores the snapshot through the server', (tester) async {
    final h = await withHistory();
    await pumpCoach(tester, h);

    await tester.tap(find.text('Deshacer los últimos cambios del Coach'));
    await tester.pumpAndSettle();
    expect(find.text('¿Deshacer los últimos cambios del Coach?'), findsOneWidget);
    expect(find.textContaining('Tu plan vuelve a como estaba antes de aceptarlos.'), findsOneWidget);
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();

    expect(h.writes.single.$1, 'POST /api/proposals/p0/revert');
    final docs = {for (final d in h.lastWrite['docs'] as List) (d as Map)['key']: d['data'] as Map};
    expect(docs.keys, ['plan', 'coach']);
    expect(docs['plan']!['routines'][0]['ex'][0]['sets'], 3);
    expect(docs['coach']!['snapshots'], isEmpty);

    expect(h.app.plan.routines.first.ex.first.sets, 3);
    expect(h.app.coach.snapshots, isEmpty);
    final entry = h.app.coach.log.last;
    expect(entry['kind'], 'revert');
    expect(entry['proposalId'], 'p0');
    expect(entry['snapshotAt'], createdAt - 5 * day);
    expect(h.app.proposalById('p0')!.revertedAt, isNotNull);
    expect(find.text('Plan restaurado'), findsOneWidget);
    expect(find.text('Deshacer los últimos cambios del Coach'), findsNothing);
    expect(find.text('Deshizo los últimos cambios'), findsOneWidget);
    await disposeHarness(tester, h);
  });

  testWidgets('undo offline changes nothing', (tester) async {
    final h = await withHistory();
    h.offline = true;
    await pumpCoach(tester, h);
    await tester.tap(find.text('Deshacer los últimos cambios del Coach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sin conexión con tu servidor'), findsOneWidget);
    expect(h.app.plan.routines.first.ex.first.sets, 4);
    expect(h.app.coach.snapshots, hasLength(1));
    expect(h.app.hasUnsyncedChanges, isFalse);
    await disposeHarness(tester, h);
  });

  group('"Claude actualizó tu perfil"', () {
    testWidgets('shows once per Claude edit and remembers it was seen', (tester) async {
      final h = CoachHarness();
      h.server.putDoc('athlete', athleteBy('claude', createdAt));
      await h.sync();
      await pumpCoach(tester, h);
      expect(find.text('Claude actualizó tu perfil'), findsOneWidget);
      expect(find.textContaining('Actualizado por Claude el 21 sept'), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Claude actualizó tu perfil'), findsNothing);
      expect((await SharedPreferences.getInstance()).getInt('coach.athleteSeenSavedAt'), createdAt);

      // A fresh Coach screen remembers it…
      await tester.pumpWidget(const SizedBox());
      await pumpCoach(tester, h);
      expect(find.text('Claude actualizó tu perfil'), findsNothing);

      // …until Claude edits the profile again.
      h.server.putDoc('athlete', athleteBy('claude', createdAt + day));
      await h.sync();
      await tester.pumpAndSettle();
      expect(find.text('Claude actualizó tu perfil'), findsOneWidget);
      await disposeHarness(tester, h);
    });

    testWidgets('not shown for the owner\'s own saves', (tester) async {
      final h = CoachHarness();
      h.server.putDoc('athlete', athleteBy('app', createdAt));
      await h.sync();
      await pumpCoach(tester, h);
      expect(find.text('Claude actualizó tu perfil'), findsNothing);
      expect(find.text('Ganar músculo · 4 días a la semana · 60 min'), findsOneWidget);
      await disposeHarness(tester, h);
    });
  });
}
