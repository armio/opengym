import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/ui/theme.dart';
import 'package:opengym/ui/widgets/widgets.dart';

/// The grouped-list row's value (`.lrow-v`, `flex: none`): right-aligned at its natural width,
/// taking the room a short title leaves, without squeezing a long title to nothing.
void main() {
  Future<void> pumpRows(WidgetTester tester, List<Widget> rows, {double width = 320}) async {
    tester.view
      ..physicalSize = Size(width, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: Scaffold(
          body: ListView(children: [Section(children: rows)]),
        ),
      ),
    );
  }

  double lineHeight(WidgetTester tester, String text) => tester.getSize(find.text(text)).height;

  testWidgets('a short value sits at the right edge and the title keeps the rest', (tester) async {
    await pumpRows(tester, [const ListRow(title: 'Unidad', value: 'kg', accessory: RowAccessory.chevron)]);
    final row = tester.getRect(find.byType(ListRow));
    final value = tester.getRect(find.text('kg'));
    expect(row.right - value.right, lessThan(14 + 6 + 18 + 1), reason: 'only padding and the chevron after it');
    expect(tester.getRect(find.text('Unidad')).left, lessThan(row.left + 15));
  });

  // The test font draws every glyph one em (17 px) wide; the row is 320 − 28 padding − 24
  // chevron = 268 px for the title and the value.
  testWidgets('a long value takes what a short title leaves, on one line', (tester) async {
    await pumpRows(tester, [
      const ListRow(title: 'Ab', value: 'Doce letras.', accessory: RowAccessory.chevron),
      const ListRow(title: 'x', value: 'y'),
    ]);
    // About 12 × 17 px: more than the 60 % the value used to be capped at, still one line.
    expect(tester.getSize(find.text('Doce letras.')).width, closeTo(204, 3));
    expect(lineHeight(tester, 'Doce letras.'), lineHeight(tester, 'y'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('when both are long the title keeps its line and the value wraps', (tester) async {
    await pumpRows(tester, [
      const ListRow(
        icon: 'chartLine',
        title: 'Unidad',
        value: 'Sin progresión automática',
        accessory: RowAccessory.chevron,
      ),
      const ListRow(title: 'x', value: 'y'),
    ]);
    expect(lineHeight(tester, 'Unidad'), lineHeight(tester, 'x'), reason: 'the title is not squeezed');
    expect(lineHeight(tester, 'Sin progresión automática'), 2 * lineHeight(tester, 'y'), reason: 'two lines at most');
    expect(tester.takeException(), isNull);
  });
}
