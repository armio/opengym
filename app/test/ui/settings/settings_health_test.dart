import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/health/health_prefs.dart';
import 'package:opengym/data/health/health_sync.dart';
import 'package:opengym/ui/screens/settings/settings_screen.dart';
import 'package:opengym/ui/theme.dart';
import 'package:provider/provider.dart';

import '../../data/health/fake_health_bridge.dart';
import '../../widgets/test_app.dart';
import 'settings_harness.dart';

void main() {
  Finder inDialog(String text) => find.descendant(of: find.byType(Dialog), matching: find.text(text));

  Future<(SettingsHarness, FakeHealthBridge, HealthSync)> pump(WidgetTester tester, {bool supported = true}) async {
    final harness = SettingsHarness();
    final bridge = FakeHealthBridge()..supported = supported;
    final health = HealthSync(
      app: harness.app,
      bridge: bridge,
      store: MemoryHealthPrefsStore(),
      observeLifecycle: false,
      exportDelay: Duration.zero,
    );
    addTearDown(health.dispose);
    tester.view
      ..physicalSize = const Size(900, 5000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: harness.app),
          ChangeNotifierProvider<HealthSync>.value(value: health),
        ],
        child: MaterialApp(
          theme: AppTheme.build(brightness: Brightness.dark),
          home: SettingsScreen(backupFiles: harness.files),
        ),
      ),
    );
    await tester.runAsync(health.start);
    await tester.pumpAndSettle();
    return (harness, bridge, health);
  }

  testWidgets('is hidden on devices without Apple Health', (tester) async {
    final (harness, _, _) = await pump(tester, supported: false);
    expect(find.text('Apple Health'), findsNothing);
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('is hidden when no health sync is provided (tests, web)', (tester) async {
    final harness = SettingsHarness();
    await pumpSettings(tester, harness);
    expect(find.text('Apple Health'), findsNothing);
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('connects, then shows the three switches and the last run', (tester) async {
    final (harness, bridge, health) = await pump(tester);
    expect(find.text('Conectar con Apple Health'), findsOneWidget);

    await tester.tap(find.text('Conectar con Apple Health'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(bridge.authorizations, 1);
    expect(health.isConnected, isTrue);
    expect(find.text('Guardar entrenos en Salud'), findsOneWidget);
    expect(find.text('Sincronizar peso corporal'), findsOneWidget);
    expect(find.text('Compartir recuperación con Claude'), findsOneWidget);
    expect(find.text('Sincronizar ahora'), findsOneWidget);
    expect(find.text('Ahora'), findsOneWidget);
    expect(harness.routes, contains('POST /api/recovery'));
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('turning recovery sharing off deletes it on the server', (tester) async {
    final (harness, _, health) = await pump(tester);
    await tester.runAsync(health.connect);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compartir recuperación con Claude'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(health.shareRecovery, isFalse);
    expect(harness.routes, contains('POST /api/recovery/clear'));
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('disconnecting asks first', (tester) async {
    final (harness, _, health) = await pump(tester);
    await tester.runAsync(health.connect);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Desconectar Apple Health'));
    await tester.pumpAndSettle();
    expect(find.textContaining('se borrarán de tu servidor los datos de recuperación'), findsOneWidget);
    await tester.tap(inDialog('Desconectar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(health.isConnected, isFalse);
    expect(find.text('Conectar con Apple Health'), findsOneWidget);
    expect(harness.routes, contains('POST /api/recovery/clear'));
    await settleAndDispose(tester, harness.app);
  });
}
