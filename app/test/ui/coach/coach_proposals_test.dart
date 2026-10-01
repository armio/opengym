import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/coach/change_set_screen.dart';
import 'package:opengym/ui/shell.dart';
import 'package:opengym/ui/widgets/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coach_harness.dart';

/// A harness whose server holds [planJson] and [proposals], already pulled by the app.
Future<CoachHarness> seeded(List<JsonMap> proposals) async {
  final h = CoachHarness();
  h.server.putDoc('plan', planJson());
  proposals.forEach(h.addProposal);
  await h.sync();
  return h;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

AppButton button(WidgetTester tester, String label) => tester.widget<AppButton>(find.widgetWithText(AppButton, label));

List<String> docKeys(JsonMap body) => [for (final d in body['docs'] as List) (d as Map)['key'] as String];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('plan proposals', () {
    testWidgets('accepting adds the routines, replaces the week, logs and resolves it', (tester) async {
      final h = await seeded([planProposal(iteration: 2)]);
      await pumpCoach(tester, h);
      expect(find.text('Plan nuevo'), findsOneWidget);

      await tapText(tester, 'Tu plan está listo');
      expect(find.text('Plan de fuerza 2 días · Revisión 2'), findsOneWidget);
      expect(find.text('tus últimas 12 semanas'), findsOneWidget);
      expect(find.text('Los básicos primero, con descanso largo.'), findsOneWidget);
      expect(find.text('Tu press de banca progresa bien.'), findsOneWidget);
      expect(find.text('2 ejercicios'), findsOneWidget);
      expect(find.text('3 × 8'), findsNWidgets(2));
      expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isTrue);

      await tapText(tester, 'Aceptar plan');

      expect(h.writes.single.$1, 'POST /api/proposals/pPlan/resolve');
      final body = h.lastWrite;
      expect(body['outcome'], 'applied');
      expect(body['accepted'], ['plan']);
      expect(body['schedule'], isTrue);
      expect(docKeys(body), ['plan', 'coach']);

      final plan = h.app.plan;
      expect(plan.routines.map((r) => r.name), ['Full body A', 'Full body B', 'Empuje y pierna', 'Tirón']);
      final added = plan.routines.sublist(2);
      expect(plan.week, {'2': added[0].id, '4': added[1].id});
      expect(added[0].toJson().containsKey('why'), isFalse, reason: 'reasons are not part of the plan');
      expect(added[1].ex.map((e) => e.id), ['0652', '0027', '0294']);

      final coach = h.app.coach;
      expect(coach.log.single, containsPair('kind', 'create'));
      expect(coach.log.single, containsPair('proposalId', 'pPlan'));
      expect(coach.log.single, containsPair('routines', 2));
      expect(coach.snapshots.single.proposalId, 'pPlan');
      expect(coach.snapshots.single.routines.map((r) => r.id), ['r1', 'r2']);
      expect(coach.snapshots.single.week, {'1': 'r1', '3': 'r2', '5': 'r1'});

      final proposal = h.app.proposalById('pPlan')!;
      expect(proposal.status, 'applied');
      expect(proposal.resolution!.schedule, isTrue);
      expect(h.app.pendingProposals, isEmpty);
      expect(h.app.hasUnsyncedChanges, isFalse, reason: 'the server already has the docs');
      expect(find.text('Tu plan ya está activo'), findsOneWidget);
      expect(h.shell.tab, AppTab.plan);
      await disposeHarness(tester, h);
    });

    testWidgets('with the weekly schedule switched off the week is kept', (tester) async {
      final h = await seeded([planProposal()]);
      await pumpCoach(tester, h);
      await tapText(tester, 'Tu plan está listo');
      expect(find.text('Plan de fuerza 2 días'), findsOneWidget);

      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();
      await tapText(tester, 'Aceptar plan');

      expect(h.lastWrite['schedule'], isFalse);
      expect(h.app.plan.routines, hasLength(4));
      expect(h.app.plan.week, {'1': 'r1', '3': 'r2', '5': 'r1'});
      await disposeHarness(tester, h);
    });

    testWidgets('"Descartar" asks first, then logs the dismissal and leaves the plan alone', (tester) async {
      final h = await seeded([planProposal()]);
      await pumpCoach(tester, h);
      await tapText(tester, 'Tu plan está listo');

      await tapText(tester, 'Descartar');
      expect(find.text('¿Descartar este plan?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(h.writes, isEmpty);

      await tapText(tester, 'Descartar');
      await tapText(tester, 'Descartar');

      final body = h.lastWrite;
      expect(body['outcome'], 'dismissed');
      expect(body['accepted'], isEmpty);
      expect(docKeys(body), ['coach'], reason: 'the plan did not change');
      expect(h.app.plan.routines.map((r) => r.id), ['r1', 'r2']);
      expect(h.app.coach.log.single, containsPair('dismissed', true));
      expect(h.app.coach.snapshots, isEmpty);
      expect(h.app.proposalById('pPlan')!.status, 'dismissed');
      expect(find.text('Plan descartado'), findsOneWidget);
      expect(h.shell.tab, AppTab.coach);
      expect(find.textContaining('No hay propuestas pendientes.'), findsOneWidget);
      await disposeHarness(tester, h);
    });

    testWidgets('a proposal in another unit cannot be accepted', (tester) async {
      final h = await seeded([planProposal(unit: 'lb')]);
      await pumpCoach(tester, h);
      await tapText(tester, 'Tu plan está listo');

      expect(find.text('Unidad distinta'), findsOneWidget);
      expect(find.text('La propuesta usa lb; cambia la unidad o pide una nueva.'), findsOneWidget);
      expect(button(tester, 'Aceptar plan').onPressed, isNull);
      await tester.tap(find.text('Aceptar plan'));
      await tester.pumpAndSettle();

      expect(h.writes, isEmpty);
      expect(h.app.plan.routines, hasLength(2));
      expect(h.app.proposalById('pPlan')!.status, 'pending');
      await disposeHarness(tester, h);
    });
  });

  group('change sets', () {
    testWidgets('applies the ticked subset; stale changes have no checkbox and are reported', (tester) async {
      final h = await seeded([changesProposal(planHash: hashOf(planJson()))]);
      await pumpCoach(tester, h);
      expect(find.text('Cambios'), findsOneWidget);
      await tapText(tester, 'Sugerencias listas');

      expect(find.textContaining('Basado en tus últimas 12 sesiones'), findsOneWidget);
      expect(find.textContaining('Tu plan cambió'), findsNothing, reason: 'the plan hash still matches');
      expect(find.text('Barbell Bench Press: series'), findsOneWidget);
      expect(find.text('Barbell Full Squat: series'), findsOneWidget);
      expect(find.text(staleNote), findsOneWidget);
      expect(find.text('Tu peso lleva cuatro semanas estable: si quieres ganar, come algo más.'), findsOneWidget);

      final cards = tester.widgetList<ChangeCard>(find.byType(ChangeCard)).toList();
      expect([for (final c in cards) c.ticked], [true, true, null], reason: 'the stale change cannot be ticked');
      expect(find.byType(RoundCheck), findsNWidgets(2));
      expect(find.text('Aplicar 2 cambios'), findsOneWidget);

      await tester.tap(find.byType(RoundCheck).at(1));
      await tester.pumpAndSettle();
      await tapText(tester, 'Aplicar 1 cambio');

      final body = h.lastWrite;
      expect(h.writes.single.$1, 'POST /api/proposals/pChanges/resolve');
      expect(body['outcome'], 'applied');
      expect(body['accepted'], ['c1']);
      expect(body['rejected'], ['c2']);
      expect(body['stale'], ['c3']);
      expect(docKeys(body), ['plan', 'coach']);

      final bench = h.app.plan.routines.first.ex.first;
      expect((bench.sets, bench.reps), (4, 10));
      expect(h.app.plan.routines[1].ex.single.sets, 4, reason: 'the stale change was not applied');
      final entry = h.app.coach.log.single;
      expect(entry['kind'], 'review');
      expect(
        [for (final d in entry['decisions'] as List) '${d['id']}:${d['status']}'],
        ['c1:accepted', 'c2:rejected', 'c3:stale'],
      );
      expect(h.app.coach.snapshots.single.proposalId, 'pChanges');
      expect(h.app.proposalById('pChanges')!.status, 'applied');
      expect(find.text('1 cambio aplicado'), findsOneWidget);
      expect(h.shell.tab, AppTab.plan);
      await disposeHarness(tester, h);
    });

    testWidgets('shows the plan-moved banner when the plan changed since Claude read it', (tester) async {
      final h = await seeded([changesProposal(planHash: 'ffffffffffffffff')]);
      await pumpCoach(tester, h);
      await tapText(tester, 'Sugerencias listas');
      expect(find.textContaining('Tu plan cambió desde que Claude lo revisó'), findsOneWidget);
      expect(find.text('Aplicar 2 cambios'), findsOneWidget, reason: 'the banner does not block fresh changes');
      await disposeHarness(tester, h);
    });

    testWidgets('with nothing ticked the button runs the dismiss flow', (tester) async {
      final h = await seeded([changesProposal()]);
      await pumpCoach(tester, h);
      await tapText(tester, 'Sugerencias listas');

      await tester.tap(find.byType(RoundCheck).at(0));
      await tester.tap(find.byType(RoundCheck).at(1));
      await tester.pumpAndSettle();
      await tapText(tester, 'No aplicar nada');
      expect(find.text('¿Descartar estas sugerencias?'), findsOneWidget);
      await tapText(tester, 'Descartar');

      final body = h.lastWrite;
      expect(body['outcome'], 'dismissed');
      expect(body['accepted'], isEmpty);
      expect(body['rejected'], ['c1', 'c2']);
      expect(body['stale'], ['c3']);
      expect(docKeys(body), ['coach']);
      expect(h.app.plan.routines.first.ex.first.sets, 3);
      expect(h.app.coach.log.single, containsPair('dismissed', true));
      expect(h.app.coach.lastReview, isNotNull);
      expect(h.app.proposalById('pChanges')!.status, 'dismissed');
      expect(find.text('Sugerencias descartadas'), findsOneWidget);
      await disposeHarness(tester, h);
    });

    testWidgets('"Descartar todo" dismisses every change', (tester) async {
      final h = await seeded([changesProposal()]);
      await pumpCoach(tester, h);
      await tapText(tester, 'Sugerencias listas');
      await tapText(tester, 'Descartar todo');
      await tapText(tester, 'Descartar');

      expect(h.lastWrite['outcome'], 'dismissed');
      expect(h.lastWrite['rejected'], ['c1', 'c2']);
      expect(h.app.pendingProposals, isEmpty);
      await disposeHarness(tester, h);
    });
  });

  testWidgets('a reading is acknowledged with "Entendido" without touching any doc', (tester) async {
    final h = await seeded([readingProposal()]);
    await pumpCoach(tester, h);
    expect(find.text('Sin cambios'), findsOneWidget);
    expect(find.text('Tu plan funciona: has subido peso en todos los básicos. Sigue así.'), findsOneWidget);

    await tapText(tester, 'Entendido');

    expect(h.writes.single.$1, 'POST /api/proposals/pReading/resolve');
    expect(h.lastWrite['outcome'], 'dismissed');
    expect(h.lastWrite['docs'], isEmpty);
    expect(h.app.coach.log, isEmpty);
    expect(h.app.proposalById('pReading')!.status, 'dismissed');
    expect(find.textContaining('No hay propuestas pendientes.'), findsOneWidget);
    await disposeHarness(tester, h);
  });

  group('failures change nothing locally', () {
    testWidgets('409: the proposal was resolved elsewhere — the server state is shown', (tester) async {
      final h = await seeded([planProposal()]);
      await pumpCoach(tester, h);
      await tapText(tester, 'Tu plan está listo');
      // Another device dismissed it; this one has not pulled yet.
      h.server.proposals['pPlan'] = {...h.server.proposals['pPlan']!, 'status': 'dismissed'};

      await tapText(tester, 'Aceptar plan');

      expect(h.writes, hasLength(1));
      expect(h.app.plan.routines.map((r) => r.id), ['r1', 'r2']);
      expect(h.app.plan.week, {'1': 'r1', '3': 'r2', '5': 'r1'});
      expect(h.app.coach.log, isEmpty);
      expect(h.app.coach.snapshots, isEmpty);
      expect(h.app.proposalById('pPlan')!.status, 'dismissed');
      expect(
        find.textContaining('Esta propuesta ya no está pendiente. Se muestra el estado del servidor.'),
        findsOneWidget,
      );
      expect(find.text('Esta propuesta ya no está pendiente'), findsOneWidget);
      expect(find.text('Aceptar plan'), findsNothing);
      expect(h.shell.tab, AppTab.coach);
      await disposeHarness(tester, h);
    });

    testWidgets('409: the plan changed on another device', (tester) async {
      final h = await seeded([changesProposal()]);
      await pumpCoach(tester, h);
      await tapText(tester, 'Sugerencias listas');
      // Another device edited the plan after this one pulled it.
      h.server.putDoc('plan', {
        ...planJson(),
        'week': {'1': 'r1'},
      });

      await tapText(tester, 'Aplicar 2 cambios');

      expect(h.writes, hasLength(1));
      expect(h.app.coach.log, isEmpty);
      expect(h.app.plan.routines.first.ex.first.sets, 3, reason: 'the draft was discarded');
      expect(find.textContaining('Tus datos cambiaron en otro dispositivo.'), findsOneWidget);
      expect(h.app.proposalById('pChanges')!.status, 'pending');
      await disposeHarness(tester, h);
    });

    testWidgets('offline: a message, nothing applied and nothing queued', (tester) async {
      final h = await seeded([changesProposal()]);
      h.offline = true;
      await pumpCoach(tester, h);
      await tapText(tester, 'Sugerencias listas');

      await tapText(tester, 'Aplicar 2 cambios');

      expect(find.textContaining('Sin conexión con tu servidor'), findsOneWidget);
      expect(h.app.plan.routines.first.ex.first.sets, 3);
      expect(h.app.coach.log, isEmpty);
      expect(h.app.hasUnsyncedChanges, isFalse);
      expect(h.app.proposalById('pChanges')!.status, 'pending');
      expect(find.text('Aplicar 2 cambios'), findsOneWidget, reason: 'still on the proposal, ready to retry');
      await disposeHarness(tester, h);
    });
  });
}

const staleNote = 'Ya no coincide con tu plan: no se puede aplicar.';
