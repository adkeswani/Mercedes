import 'dart:convert';
import 'dart:html' as html;

import 'package:stage5/features/workouts/data/workout_draft_local_store_contract.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';

const _prefix = 'mercedes.workoutCompletionDraft.';

WorkoutDraftLocalStore createWorkoutDraftLocalStore() {
  return _BrowserWorkoutDraftLocalStore();
}

class _BrowserWorkoutDraftLocalStore implements WorkoutDraftLocalStore {
  @override
  Future<void> delete(String instanceId) async {
    html.window.localStorage.remove('$_prefix$instanceId');
  }

  @override
  Future<WorkoutCompletionDraft?> read(String instanceId) async {
    final encoded = html.window.localStorage['$_prefix$instanceId'];
    if (encoded == null) {
      return null;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Local workout draft is invalid');
    }
    return WorkoutCompletionDraft.fromMap(
      Map<String, dynamic>.from(decoded),
    );
  }

  @override
  Future<void> write(WorkoutCompletionDraft draft) async {
    html.window.localStorage['$_prefix${draft.instanceId}'] =
        jsonEncode(draft.toLocalMap());
  }
}
