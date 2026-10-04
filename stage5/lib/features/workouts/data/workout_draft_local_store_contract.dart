import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';

abstract interface class WorkoutDraftLocalStore {
  Future<WorkoutCompletionDraft?> read(String instanceId);

  Future<void> write(WorkoutCompletionDraft draft);

  Future<void> delete(String instanceId);
}
