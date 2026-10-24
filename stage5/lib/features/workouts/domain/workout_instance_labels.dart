import 'package:stage5/core/enums.dart';

/// Shared label helpers for rendering a [WorkoutInstance] in list/card UIs
/// across the athlete dashboard, workout history, and related screens.

String workoutProgramLabel(String workoutName, String programName) =>
    '$workoutName - $programName';

String workoutStatusLabel(WorkoutInstanceStatus status) {
  final name = status.name;
  return '${name[0].toUpperCase()}${name.substring(1)}';
}
