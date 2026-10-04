abstract interface class WorkoutDraftClientIdStore {
  String? read();

  void write(String clientId);
}
