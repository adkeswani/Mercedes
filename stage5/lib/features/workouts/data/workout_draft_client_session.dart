import 'package:stage5/features/workouts/data/workout_draft_client_id_store_contract.dart';
import 'package:stage5/features/workouts/domain/workout_draft_client_id.dart';

class WorkoutDraftClientSession {
  WorkoutDraftClientSession({
    required WorkoutDraftClientIdStore store,
    required WorkoutDraftClientIdGenerator generator,
  })  : _store = store,
        _generator = generator;

  final WorkoutDraftClientIdStore _store;
  final WorkoutDraftClientIdGenerator _generator;

  String getOrCreateClientId() {
    final stored = _store.read();
    if (stored != null && WorkoutDraftClientIdGenerator.isValid(stored)) {
      return stored;
    }
    final generated = _generator.generate();
    if (!WorkoutDraftClientIdGenerator.isValid(generated)) {
      throw StateError('Generated workout draft client ID is invalid');
    }
    _store.write(generated);
    return generated;
  }
}
