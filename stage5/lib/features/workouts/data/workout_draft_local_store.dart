import 'package:stage5/features/workouts/data/workout_draft_local_store_contract.dart';
import 'package:stage5/features/workouts/data/workout_draft_local_store_stub.dart'
    if (dart.library.html) 'package:stage5/features/workouts/data/workout_draft_local_store_web.dart'
    as implementation;

export 'package:stage5/features/workouts/data/workout_draft_local_store_contract.dart';

WorkoutDraftLocalStore createWorkoutDraftLocalStore() {
  return implementation.createWorkoutDraftLocalStore();
}
