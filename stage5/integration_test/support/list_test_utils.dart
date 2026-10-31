import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> revealListTarget(
  WidgetTester tester,
  Finder target, {
  required Finder scrollable,
  double delta = 250,
  int maxScrolls = 40,
}) async {
  if (target.evaluate().isEmpty) {
    // A recycled target can be above or below the current viewport. Search
    // from the list's start instead of guessing a direction or scrolling a sidebar.
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.scrollUntilVisible(
    target,
    delta.abs(),
    scrollable: scrollable,
    maxScrolls: maxScrolls,
  );
  await tester.pump(const Duration(milliseconds: 100));
}
