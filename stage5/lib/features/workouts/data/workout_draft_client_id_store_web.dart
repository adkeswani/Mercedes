import 'dart:html' as html;

import 'package:stage5/features/workouts/data/workout_draft_client_id_store_contract.dart';

const _clientIdKey = 'mercedes.workoutDraftClientId.v1';

final WorkoutDraftClientIdStore _browserStore = CachedWorkoutDraftClientIdStore(
  readPersisted: () => html.window.sessionStorage[_clientIdKey],
  writePersisted: (clientId) {
    html.window.sessionStorage[_clientIdKey] = clientId;
  },
);

WorkoutDraftClientIdStore createWorkoutDraftClientIdStore() {
  return _browserStore;
}
