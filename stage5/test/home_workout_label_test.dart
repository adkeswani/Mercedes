import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/home_screen.dart';

void main() {
  test('today workout label combines workout and program names', () {
    expect(
      workoutProgramLabel('Full Body A', 'Base Strength'),
      'Full Body A - Base Strength',
    );
  });

  test('today workout status label is human-readable', () {
    expect(workoutStatusLabel(WorkoutInstanceStatus.scheduled), 'Scheduled');
    expect(workoutStatusLabel(WorkoutInstanceStatus.completed), 'Completed');
  });
}
