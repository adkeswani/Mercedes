import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/exercise_type_screenshots.dart';

void main() {
  test('captures all four legacy exercise types and completion details', () {
    expect(exerciseTypeScreenshotTargets.map((target) => target.slotId), [
      'slot-standard',
      'slot-timed',
      'slot-climbing',
      'slot-amrap',
    ]);
    expect(
      [
        ...exerciseTypeScreenshotTargets.map((target) => target.name),
        exerciseTypesCompletionScreenshot,
      ],
      [
        'athlete-standard-exercise',
        'athlete-timed-exercise',
        'athlete-climbing-route',
        'athlete-amrap-exercise',
        'athlete-exercise-types-completion',
      ],
    );
    for (final target in exerciseTypeScreenshotTargets) {
      expect(target.title, isNotEmpty);
    }
  });
}
