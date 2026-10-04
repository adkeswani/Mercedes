import 'package:stage5/features/workouts/data/workout_draft_local_store_contract.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';

WorkoutDraftLocalStore createWorkoutDraftLocalStore() {
  return _MemoryWorkoutDraftLocalStore();
}

class _MemoryWorkoutDraftLocalStore implements WorkoutDraftLocalStore {
  final _drafts = <String, WorkoutCompletionDraft>{};

  @override
  Future<void> delete(String instanceId) async {
    _drafts.remove(instanceId);
  }

  @override
  Future<WorkoutCompletionDraft?> read(String instanceId) async {
    return _drafts[instanceId];
  }

  @override
  Future<void> write(WorkoutCompletionDraft draft) async {
    _drafts[draft.instanceId] = draft;
  }
}
