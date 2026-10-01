import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import '../../widgets/test_app.dart';
import 'settings_harness.dart';

void main() {
  Finder segment(String label) => find.descendant(of: find.byType(Segmented<String>), matching: find.text(label));
  Finder switchOf(String title) =>
      find.descendant(of: find.widgetWithText(SwitchRow, title), matching: find.byType(AppSwitch));

  testWidgets('every preference writes through AppState.updateSettings', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SettingsHarness();
    final app = harness.app..updateSettings((s) => s.showRir = true);
    await pumpSettings(tester, harness);

    await tester.tap(segment('lb'));
    await tester.pump();
    expect(app.settings.unit, 'lb');

    await tester.tap(find.text('Temporizador de descanso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('120 s'));
    await tester.pumpAndSettle();
    expect(app.settings.restSec, 120);
    expect(find.text('120 s'), findsOneWidget, reason: 'the row shows the new value');

    await tester.tap(switchOf('Mantener la pantalla encendida'));
    await tester.tap(switchOf('Sonidos'));
    await tester.pump();
    expect(app.settings.keepAwake, isFalse);
    expect(app.settings.sound, isFalse);

    expect(app.settings.effortScale, 'rir', reason: 'legacy showRir reads as RIR');
    await tester.tap(segment('RPE'));
    await tester.pump();
    expect(app.settings.effort, 'rpe');
    expect(app.settings.toJson(), isNot(contains('showRir')), reason: 'choosing a scale deletes showRir');

    await tester.tap(segment('Mini'));
    await tester.tap(segment('Claro'));
    await tester.tap(segment('Femenino'));
    await tester.pump();
    expect(app.settings.gifSize, 'mini');
    expect(app.settings.theme, 'light');
    expect(app.settings.body, 'female');

    await tester.tap(find.bySemanticsLabel('Cielo'));
    await tester.pump();
    expect(app.settings.accent, 'sky');

    // The edits are one dirty settings doc, pushed on the next sync.
    await tester.pump(const Duration(seconds: 3));
    final pushed = harness.server.docs['settings']!['data'] as Map<String, dynamic>;
    expect(pushed['unit'], 'lb');
    expect(pushed['accent'], 'sky');
    semantics.dispose();
    await settleAndDispose(tester, app);
  });

  testWidgets('the goal row opens the goal sheet and shows the goal', (tester) async {
    final harness = SettingsHarness();
    await pumpSettings(tester, harness);
    expect(find.text('Sin meta'), findsOneWidget);

    await tester.tap(find.text('Peso objetivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar meta'));
    await tester.pumpAndSettle();
    expect(harness.app.settings.targetW, 70);
    expect(find.text('70 kg'), findsOneWidget);
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('the (i) button explains RIR and RPE', (tester) async {
    final harness = SettingsHarness();
    await pumpSettings(tester, harness);

    await tester.tap(find.byTooltip('¿Qué son RIR y RPE?'));
    await tester.pumpAndSettle();
    expect(find.text('CÓMO SE SINTIÓ'), findsOneWidget);
    expect(find.text('Dos repeticiones más'), findsOneWidget);
    await settleAndDispose(tester, harness.app);
  });

  testWidgets('lays out at phone width', (tester) async {
    final harness = SettingsHarness();
    await pumpSettings(tester, harness, width: 360);
    expect(find.text('Acerca de'), findsOneWidget);
    await tester.tap(find.byTooltip('¿Qué son RIR y RPE?'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await settleAndDispose(tester, harness.app);
  });
}
