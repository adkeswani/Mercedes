abstract interface class WorkoutDraftClientIdStore {
  String? read();

  void write(String clientId);
}

typedef WorkoutDraftClientIdReader = String? Function();
typedef WorkoutDraftClientIdWriter = void Function(String clientId);

class CachedWorkoutDraftClientIdStore implements WorkoutDraftClientIdStore {
  CachedWorkoutDraftClientIdStore({
    required WorkoutDraftClientIdReader readPersisted,
    required WorkoutDraftClientIdWriter writePersisted,
  })  : _readPersisted = readPersisted,
        _writePersisted = writePersisted;

  final WorkoutDraftClientIdReader _readPersisted;
  final WorkoutDraftClientIdWriter _writePersisted;
  String? _cached;

  @override
  String? read() => _cached ??= _readPersisted();

  @override
  void write(String clientId) {
    _writePersisted(clientId);
    _cached = clientId;
  }
}
