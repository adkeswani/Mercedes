import 'package:stage5/features/workouts/data/workout_draft_client_id_store_contract.dart';

final _processStore = _MemoryWorkoutDraftClientIdStore();

WorkoutDraftClientIdStore createWorkoutDraftClientIdStore() {
  return _processStore;
}

class _MemoryWorkoutDraftClientIdStore implements WorkoutDraftClientIdStore {
  String? _clientId;

  @override
  String? read() => _clientId;

  @override
  void write(String clientId) {
    _clientId = clientId;
  }
}
