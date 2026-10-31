import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Finder> revealDropdownOption<T>(
  WidgetTester tester,
  Finder field,
  T value,
) async {
  final button = tester.widget<DropdownButton<T>>(find.descendant(
    of: field,
    matching: find.byType(DropdownButton<T>),
  ));
  final options = button.items!;
  final targetIndex = options.indexWhere((item) => item.value == value);
  if (targetIndex < 0) throw StateError('Dropdown has no option for $value');
  final selectedIndex =
      options.indexWhere((item) => item.value == button.value);
  final popup = find.byType(Scrollable).last;
  final option = find.descendant(
    of: popup,
    matching: find.byWidgetPredicate(
      (widget) => widget is DropdownMenuItem<T> && widget.value == value,
    ),
  );
  await tester.scrollUntilVisible(
    option,
    targetIndex < selectedIndex ? -120 : 120,
    scrollable: popup,
    maxScrolls: 35,
  );
  await tester.pump(const Duration(milliseconds: 100));
  return find.descendant(of: option, matching: find.byType(Text));
}
