import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../widgets/test_app.dart';
import 'settings_harness.dart';

void main() {
  Finder inDialog(String text) => find.descendant(of: find.byType(Dialog), matching: find.text(text));

  testWidgets('shows the server, this device and the Claude connector URL with a copy button', (tester) async {
    final harness = SettingsHarness();
    final copied = captureClipboard(tester);
    await pumpSettings(tester, harness);

    expect(find.text('https://gym.example.com'), findsOneWidget);
    expect(find.text('Pixel'), findsOneWidget);
    expect(find.text('https://gym.example.com/mcp'), findsOneWidget);

    await tester.tap(find.byTooltip('Copiar').first);
    await tester.pump();
    expect(copied(), 'https://gym.example.com/mcp');
    expect(find.text('URL del conector copiada'), findsOneWidget);
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('lists the devices and revokes another one after confirming', (tester) async {
    final harness = SettingsHarness();
    await pumpSettings(tester, harness);

    await tester.tap(find.text('Dispositivos conectados'));
    await tester.pumpAndSettle();
    expect(find.text('Este dispositivo'), findsOneWidget);
    expect(find.text('iPad'), findsOneWidget);
    expect(find.text('Revocar'), findsOneWidget, reason: 'only the other device can be revoked here');

    await tester.tap(find.text('Revocar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Revocar «iPad»?'), findsOneWidget);
    await tester.tap(inDialog('Revocar'));
    await tester.pumpAndSettle();
    expect(harness.routes, contains('POST /api/devices/d2/revoke'));
    expect(find.text('Dispositivo revocado'), findsOneWidget);
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('"Revocar acceso de Claude" asks first, then revokes every grant', (tester) async {
    final harness = SettingsHarness();
    await pumpSettings(tester, harness);

    await tester.tap(find.text('Revocar acceso de Claude'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Cancelar'));
    await tester.pumpAndSettle();
    expect(harness.routes, isNot(contains('POST /api/oauth/revoke-all')));

    await tester.tap(find.text('Revocar acceso de Claude'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Revocar'));
    await tester.pumpAndSettle();
    expect(harness.routes, contains('POST /api/oauth/revoke-all'));
    expect(find.text('Acceso de Claude revocado'), findsOneWidget);
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('"Cerrar sesión" pushes pending changes, revokes the token and clears the device', (tester) async {
    final harness = SettingsHarness();
    final app = harness.app..setBodyWeight(80);
    await pumpSettings(tester, harness);

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(harness.server.bodyweight['2026-09-30']?['w'], 80, reason: 'pushed before signing out');
    expect(harness.routes, contains('POST /api/auth/logout'));
    expect(app.isSignedIn, isFalse);
    expect(app.bodyWeights, isEmpty);
    await settleAndDispose(tester, app);
  });
}
