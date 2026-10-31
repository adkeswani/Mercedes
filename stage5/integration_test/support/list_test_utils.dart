import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> revealListTarget(
  WidgetTester tester,
  Finder target, {
  required Finder scrollable,
  double delta = 250,
  int maxScrolls = 40,
}) async {
  if (maxScrolls < 1 || !delta.isFinite || delta == 0) {
    throw ArgumentError(
        'List reveal needs a positive budget and nonzero delta');
  }
  final scrollables = scrollable.evaluate().toList();
  if (scrollables.length != 1 ||
      scrollables.single is! StatefulElement ||
      (scrollables.single as StatefulElement).state is! ScrollableState) {
    throw StateError(
      'List reveal expected one Scrollable for $scrollable; '
      'found ${scrollables.length}. Target: $target',
    );
  }
  final element = scrollables.single as StatefulElement;
  final state = element.state as ScrollableState;
  final position = state.position;
  var searchedFromStart = false;
  var attempts = 0;

  StateError failure(String reason) => StateError(
        'List reveal failed: $reason. Target: $target. Scrollable: $scrollable. '
        'Attempts: $attempts/$maxScrolls. Mounted: ${state.mounted}. '
        'Offset: ${position.hasPixels ? position.pixels : 'unavailable'}. '
        'Range: ${position.hasContentDimensions ? '${position.minScrollExtent}..${position.maxScrollExtent}' : 'unavailable'}.',
      );

  void verifyIdentity() {
    if (!state.mounted ||
        !identical(state.position, position) ||
        !scrollable.evaluate().contains(element)) {
      throw failure('the original scrollable was removed or replaced');
    }
  }

  List<Element> matches() {
    final elements = target.evaluate().toList();
    if (elements.length > 1) {
      throw failure('target is ambiguous (${elements.length} matches)');
    }
    return elements;
  }

  for (attempts = 1; attempts <= maxScrolls; attempts++) {
    verifyIdentity();
    final found = matches();
    if (found.isNotEmpty && found.single.findRenderObject()?.attached == true) {
      await Scrollable.ensureVisible(found.single);
      await tester.pump(const Duration(milliseconds: 100));
      verifyIdentity();
      final revealed = matches();
      if (revealed.isNotEmpty && _isVisible(revealed.single)) {
        return;
      }
    }
    if (!position.hasContentDimensions) {
      await tester.pump(const Duration(milliseconds: 100));
      continue;
    }
    // Reset only once when a target is absent or recycled during layout.
    // Position the captured list directly: a drag can hit nested instructions.
    final offset = searchedFromStart
        ? (position.pixels + delta.abs())
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble()
        : position.minScrollExtent;
    searchedFromStart = true;
    position.jumpTo(offset);
    await tester.pump(const Duration(milliseconds: 100));
  }
  attempts = maxScrolls;
  throw failure('target did not remain mounted and visible after layout');
}

bool _isVisible(Element element) {
  if (!element.mounted) {
    return false;
  }
  final target = element.findRenderObject();
  final viewport = Scrollable.maybeOf(element)?.context.findRenderObject();
  if (target is! RenderBox ||
      viewport is! RenderBox ||
      !target.attached ||
      !viewport.attached ||
      !target.hasSize ||
      !viewport.hasSize) {
    return false;
  }
  final bounds = Rect.fromPoints(
    viewport.globalToLocal(target.localToGlobal(Offset.zero)),
    viewport.globalToLocal(
        target.localToGlobal(target.size.bottomRight(Offset.zero))),
  );
  return (Offset.zero & viewport.size).overlaps(bounds);
}
