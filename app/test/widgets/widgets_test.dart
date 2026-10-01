import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/ui/theme.dart';
import 'package:opengym/ui/widgets/widgets.dart';

import 'test_app.dart';

void main() {
  group('NumberField parsing (comma decimals)', () {
    void check(String raw, String draft, num? value, {bool decimal = true, bool nullable = false}) {
      final r = parseNumberInput(raw, decimal: decimal, nullable: nullable);
      expect(r.draft, draft, reason: 'draft of "$raw"');
      expect(r.value, value, reason: 'value of "$raw"');
    }

    test('vectors', () {
      check('33,', '33.', 33);
      check('33,5', '33.5', 33.5);
      check('1.2.3', '1.23', 1.23);
      check(',5', '.5', 0.5);
      check('12.5', '12', 12, decimal: false);
      check('', '', 0);
      check('', '', null, nullable: true);
      check('.', '.', null, nullable: true);
      check('abc', '', 0);
      check('-3', '3', 3);
    });

    test('stepper steps round to two decimals and never go negative', () {
      expect(stepValue(0.1, 0.2, 1), 0.3);
      expect(stepValue(null, 2.5, 1), 2.5);
      expect(stepValue(1, 2.5, -1), 0);
      expect(stepValue(60, 2.5, 1), 62.5);
    });

    testWidgets('keeps the typed draft while focused and shows the value on blur', (tester) async {
      num? value = 10;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: Brightness.dark),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  NumberField(value: value, onChanged: (v) => setState(() => value = v)),
                  const TextField(key: Key('other')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(NumberField), '33,');
      await tester.pump();
      expect(value, 33);
      expect(find.text('33.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('other')));
      await tester.pump();
      expect(find.text('33'), findsOneWidget);
    });
  });

  group('formatting', () {
    test('formatNum rounds to one decimal with Spanish separators, like JS', () {
      expect(formatNum(60), '60');
      expect(formatNum(62.25), '62,3');
      expect(formatNum(78.7), '78,7');
      expect(formatNum(1234.5), '1234,5');
      expect(formatNum(12345), '12.345');
      expect(formatNum(-1.25), '-1,2');
      expect(formatNum(-0.04), '0');
    });

    test('formatDate', () {
      expect(formatDate('2026-09-30'), '30 sept');
      expect(formatDate('2026-09-30', long: true), 'mié, 30 sept');
      expect(formatDate('bad'), 'bad');
      expect(formatDateFull(DateTime(2026, 9, 30)), 'miércoles, 30 de septiembre');
    });

    test('capitalizeWords behaves like CSS capitalize', () {
      expect(capitalizeWords('barbell bench press'), 'Barbell Bench Press');
      expect(capitalizeWords('3/4 sit-up'), '3/4 Sit-up');
      expect(capitalizeWords('astride jumps (male)'), 'Astride Jumps (Male)');
      expect(capitalizeWords('cable triceps pushdown (v-bar)'), 'Cable Triceps Pushdown (V-bar)');
    });
  });

  test('glyphOf maps icon keys and legacy emoji', () {
    expect(glyphOf(null), 'figureStrength');
    expect(glyphOf(''), 'figureStrength');
    expect(glyphOf('barbell'), 'barbell');
    expect(glyphOf('trophy'), 'trophy', reason: 'any icon name passes');
    expect(glyphOf('💪'), 'arm');
    expect(glyphOf('🏋️'), 'dumbbell');
    expect(glyphOf('🏃‍♀️'), 'figureRun');
    expect(glyphOf('🏋️‍♂️'), 'dumbbell', reason: 'first code point after stripping VS16/ZWJ');
    expect(glyphOf('🙂'), 'figureStrength');
    expect(glyphKeys, hasLength(20));
    for (final key in glyphKeys) {
      expect(AppIcons.has(key), isTrue, reason: key);
    }
  });

  test('the palette follows the spec tokens and accents', () {
    final dark = AppPalette.forTheme(brightness: Brightness.dark, accent: Accent.lime);
    expect(dark.bg, const Color(0xFF000000));
    expect(dark.surface, const Color(0xFF1C1C1E));
    expect(dark.acc, const Color(0xFF30D158));
    expect(dark.onAcc, Colors.black);
    final light = AppPalette.forTheme(brightness: Brightness.light, accent: Accent.sky);
    expect(light.bg, const Color(0xFFF2F2F7));
    expect(light.acc, const Color(0xFF007AFF));
    expect(light.onAcc, Colors.white);
    expect(Accent.fromKey('unknown'), Accent.lime);
    expect(dark.heatCell(0), dark.surface2);
    expect(dark.heatCell(4), dark.acc);
    expect(AppTheme.fromSettings(theme: 'light', accent: 'gold').brightness, Brightness.light);
    expect(AppTheme.fromSettings(theme: 'whatever', accent: 'gold').brightness, Brightness.dark);
  });

  testWidgets('segmented control reports taps; switch toggles', (tester) async {
    String unit = 'kg';
    bool on = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                Segmented<String>(
                  segments: const [Segment('kg', 'kg'), Segment('lb', 'lb')],
                  value: unit,
                  onChanged: (v) => setState(() => unit = v),
                ),
                SwitchRow(title: 'Sonidos', value: on, onChanged: (v) => setState(() => on = v)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('lb'));
    await tester.pumpAndSettle();
    expect(unit, 'lb');
    await tester.tap(find.text('Sonidos'));
    await tester.pumpAndSettle();
    expect(on, isTrue);
  });

  testWidgets('showConfirm resolves true on confirm and false on cancel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final context = tester.element(find.byType(SizedBox));

    final yes = showConfirm(context, title: '¿Borrar?', message: 'Seguro', confirmText: 'Borrar', danger: true);
    await tester.pumpAndSettle();
    expect(find.text('¿Borrar?'), findsOneWidget);
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();
    expect(await yes, isTrue);

    final no = showConfirm(context, message: 'Seguro');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await no, isFalse);
  });

  testWidgets('a locked showConfirm ignores the backdrop and back; only its buttons answer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final context = tester.element(find.byType(SizedBox));

    final answer = showConfirm(
      context,
      message: '¿Subir?',
      confirmText: 'Subir',
      cancelText: 'Descartar',
      locked: true,
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5)); // the barrier
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('¿Subir?'), findsOneWidget);
    await tester.tap(find.text('Subir'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  testWidgets('toasts show one message at a time and disappear after 2.2 s', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final context = tester.element(find.byType(SizedBox));
    showToast(context, 'Peso guardado');
    await tester.pump();
    expect(find.text('Peso guardado'), findsOneWidget);
    showToast(context, 'Meta eliminada');
    await tester.pump();
    expect(find.text('Peso guardado'), findsNothing);
    expect(find.text('Meta eliminada'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Meta eliminada'), findsNothing);
  });

  testWidgets('the body-weight sheet saves today\'s weigh-in and returns it', (tester) async {
    final app = testAppState();
    await pumpWithApp(tester, app, const Scaffold(body: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    final result = showBodyWeightSheet(context);
    await tester.pumpAndSettle();
    expect(find.text('Registrar peso corporal'), findsOneWidget);
    expect(find.text('70 kg', findRichText: true), findsOneWidget, reason: 'default without history');
    await tester.tap(find.text('+0,5'));
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(await result, 70.5);
    expect(app.bodyWeights.single.d, '2026-09-30');
    expect(app.bodyWeights.single.w, 70.5);
    await settleAndDispose(tester, app);
  });

  testWidgets('the check-in sheet is locked and offers three ways out', (tester) async {
    final app = testAppState()..setBodyWeight(80, date: '2026-09-29');
    await pumpWithApp(tester, app, const Scaffold(body: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    final result = showCheckInSheet(context);
    await tester.pumpAndSettle();
    expect(find.text('Chequeo rápido'), findsOneWidget);
    expect(find.text('80 kg', findRichText: true), findsOneWidget, reason: 'starts from the last weigh-in');

    await tester.tapAt(const Offset(10, 10)); // backdrop: locked, nothing happens
    await tester.pumpAndSettle();
    expect(find.text('Chequeo rápido'), findsOneWidget);

    await tester.tap(find.text('Empezar sin pesarse'));
    await tester.pumpAndSettle();
    final r = await result;
    expect(r.start, isTrue);
    expect(r.bodyWeight, isNull);

    final other = showCheckInSheet(context);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir otro entrenamiento'));
    await tester.pumpAndSettle();
    expect((await other).start, isFalse);
    await settleAndDispose(tester, app);
  });

  testWidgets('the goal sheet sets and removes the goal', (tester) async {
    final app = testAppState();
    await pumpWithApp(tester, app, const Scaffold(body: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    showGoalSheet(context);
    await tester.pumpAndSettle();
    await tester.tap(find.text('−1'));
    await tester.pump();
    await tester.tap(find.text('Guardar meta'));
    await tester.pumpAndSettle();
    expect(app.settings.targetW, 69);

    showGoalSheet(context);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar meta'));
    await tester.pumpAndSettle();
    expect(app.settings.targetW, isNull);
    await settleAndDispose(tester, app);
  });

  test('weight input helpers', () {
    expect(roundWeight(78.66), 78.7);
    expect(weightInputMax('lb'), 660);
    expect(weightInputMax('kg'), 300);
  });

  testWidgets('body-weight deltas are coloured towards / away from the goal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final context = tester.element(find.byType(SizedBox));
    final p = context.palette;
    expect(bodyWeightDeltaColor(context, 0, 80, 75), p.label2);
    expect(bodyWeightDeltaColor(context, -0.5, 80, null), p.label);
    expect(bodyWeightDeltaColor(context, -0.5, 80, 75), p.acc);
    expect(bodyWeightDeltaColor(context, 0.5, 80, 75), p.red);
    expect(bodyWeightDeltaColor(context, 0.5, 70, 75), p.acc);
  });

  testWidgets('sync status text reflects the app state', (tester) async {
    final app = testAppState();
    expect(syncStatusText(app), 'Todo sincronizado');
    app.setBodyWeight(80);
    expect(syncStatusText(app), 'Cambios pendientes de sincronizar');
    expect(app.syncStatus, SyncStatus.idle);
    await settleAndDispose(tester, app);
  });
}
