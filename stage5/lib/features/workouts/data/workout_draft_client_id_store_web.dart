import 'dart:html' as html;

import 'package:stage5/features/workouts/data/workout_draft_client_id_store_contract.dart';

const _clientIdKey = 'mercedes.workoutDraftClientId.v1';

WorkoutDraftClientIdStore createWorkoutDraftClientIdStore() {
  return _BrowserWorkoutDraftClientIdStore();
}

class _BrowserWorkoutDraftClientIdStore implements WorkoutDraftClientIdStore {
  @override
  String? read() => html.window.sessionStorage[_clientIdKey];

  @override
  void write(String clientId) {
    html.window.sessionStorage[_clientIdKey] = clientId;
  }
}
