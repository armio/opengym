import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tall logical viewport so long lists and sheets build every row without scrolling;
/// [width] 360 checks the phone layout.
void useTallView(WidgetTester tester, {double width = 900}) {
  tester.view
    ..physicalSize = Size(width, 5000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
