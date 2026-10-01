import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/coach/coach_screen.dart';
import 'package:opengym/ui/screens/home/home_screen.dart';
import 'package:opengym/ui/screens/login/login_screen.dart';
import 'package:opengym/ui/screens/plan/plan_screen.dart';
import 'package:opengym/ui/screens/progress/progress_screen.dart';
import 'package:opengym/ui/screens/workout/workout_screen.dart';
import 'package:opengym/ui/shell.dart';

import '../data/fake_server.dart';
import 'test_app.dart';

Finder tabLabel(String text) => find.descendant(of: find.byType(AppTabBar), matching: find.text(text));

void main() {
  testWidgets('signed in: the shell shows the five destinations and switches tabs', (tester) async {
    final app = testAppState();
    await tester.pumpWidget(OpenGymApp(appState: app));
    await tester.pump();

    for (final label in ['Inicio', 'Plan', 'Entrenar', 'Progreso', 'Coach']) {
      expect(tabLabel(label), findsOneWidget, reason: label);
    }
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(tabLabel('Plan'));
    await tester.pump();
    expect(find.byType(PlanScreen), findsOneWidget);

    await tester.tap(tabLabel('Progreso'));
    await tester.pump();
    expect(find.byType(ProgressScreen), findsOneWidget);

    await tester.tap(tabLabel('Coach'));
    await tester.pump();
    expect(find.byType(CoachScreen), findsOneWidget);

    await settleAndDispose(tester, app);
  });

  testWidgets('the centre button opens the workout and turns into "Seguir" while one is active', (tester) async {
    final app = testAppState();
    await tester.pumpWidget(OpenGymApp(appState: app));
    await tester.pump();

    await tester.tap(tabLabel('Entrenar'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();

    await app.startActive(ActiveWorkout(id: 'a1', d: '2026-09-30', start: 1, name: 'Push'));
    await tester.pump();
    expect(tabLabel('Seguir'), findsOneWidget);
    expect(tabLabel('Entrenar'), findsNothing);

    await app.discardActive();
    await settleAndDispose(tester, app);
  });

  testWidgets('the shell syncs on start and marks pending Claude proposals', (tester) async {
    final server = FakeSyncServer()
      ..putProposal({'id': 'p1', 'kind': 'nochange', 'status': 'pending', 'reading': 'Bien', 'createdAt': 1});
    final app = testAppState(server: server);
    await tester.pumpWidget(OpenGymApp(appState: app));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(server.requests, isNotEmpty);
    expect(app.pendingProposals.single.id, 'p1');

    await settleAndDispose(tester, app);
  });

  testWidgets('signed out: the login screen shows Spanish errors, then signs in', (tester) async {
    final server = FakeSyncServer()..putWorkout(workoutJson('w1'));
    final app = testAppState(signedIn: false, server: server);
    await tester.pumpWidget(OpenGymApp(appState: app));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://gym.example.com');
    await tester.enterText(fields.at(1), 'x');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.textContaining('https://'), findsWidgets); // the scheme error

    await tester.enterText(fields.at(0), 'gym.example.com');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Contraseña incorrecta'), findsOneWidget);

    await tester.enterText(fields.at(1), 'correct horse battery');
    await tester.tap(find.text('Entrar'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(app.isSignedIn, isTrue);
    expect(find.byType(AppTabBar), findsOneWidget);
    expect(app.workouts.single.id, 'w1');

    await settleAndDispose(tester, app);
  });
}
