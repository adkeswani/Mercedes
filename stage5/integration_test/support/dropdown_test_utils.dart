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
  final fieldScrollables = find
      .ancestor(of: field, matching: find.byType(Scrollable))
      .evaluate()
      .toSet();
  final popups = find
      .ancestor(
        of: find.byWidget(options[selectedIndex < 0 ? 0 : selectedIndex]),
        matching: find.byType(Scrollable),
      )
      .evaluate()
      .where((element) => !fieldScrollables.contains(element))
      .toList();
  if (popups.length != 1) {
    throw StateError('Expected one opened dropdown scrollable; '
        'found ${popups.length} for $value');
  }
  final popup = find.byElementPredicate(
    (element) => identical(element, popups.single),
    description: 'the opened dropdown scrollable',
  );
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
