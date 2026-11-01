import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/browser_test_wait.dart';
import '../integration_test/support/workout_draft_diagnostics.dart';

void main() {
  test('writer events contain only allowlisted metadata in sequence', () {
    final logs = <String>[];
    final diagnostics = WorkoutDraftDiagnostics(write: logs.add);
    diagnostics.record({
      'operation': 1,
      'editorId': 101,
      'repositoryId': 202,
      'phase': 'save-start',
      'workoutId': 'instance-1',
      'clientId': 'current',
      'revision': 4,
      'notes': 'PRIVATE NOTE',
      'credentials': 'PRIVATE TOKEN',
      'athleteId': 'PRIVATE ATHLETE',
    });
    diagnostics.record({'operation': 1, 'phase': 'save-return'});
    expect(logs.first, contains('sequence=1'));
    expect(logs.first,
        contains('executionId=${WorkoutDraftDiagnostics.executionId}'));
    expect(logs.last,
        contains('executionId=${WorkoutDraftDiagnostics.executionId}'));
    expect(logs.first, contains('pageUrl='));
    expect(logs.first, contains('editorId=101'));
    expect(logs.first, contains('repositoryId=202'));
    expect(logs.last, contains('sequence=2'));
    expect(logs.join(), isNot(contains('PRIVATE')));
    expect(logs.join(), isNot(contains('notes')));
  });

  test('conflict fails immediately without entering screenshot protocol',
      () async {
    final logs = <String>[];
    final diagnostics = WorkoutDraftDiagnostics(write: logs.add);
    final failure = diagnostics.conflictFailure(
      workoutId: 'instance-1',
      currentClientId: 'current-client',
    );
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'climbing',
      artifactPath: 'artifacts',
      currentRoute: () => '/athlete/workouts/instance-1',
    );
    Future<void> waitAndFail() async {
      try {
        await waits.waitForCondition(
          condition: 'save settled before RPE',
          isSatisfied: () => false,
          pump: () async => throw failure,
          pumpTimeout: const Duration(milliseconds: 1),
        );
      } on WorkoutDraftConflictFailure catch (error, stack) {
        diagnostics.failConflict(error, stack);
      }
    }

    await expectLater(waitAndFail(), throwsA(same(failure)));
    expect(logs.last, startsWith('BROWSER_WORKOUT_DRAFT_CONFLICT|'));
    expect(logs.join(), isNot(contains('artifact-start')));
    expect(failure.message, contains('attemptedRevision=<not observed>'));
  });

  test('reports exact conflict metadata and preserves original failure', () {
    final logs = <String>[];
    final diagnostics = WorkoutDraftDiagnostics(write: logs.add);
    diagnostics.record({
      'operation': 3,
      'phase': 'save-result',
      'workoutId': 'instance-1',
      'clientId': 'attempted-client',
      'revision': 4,
      'serverClientId': 'authoritative-client',
      'serverRevision': 8,
      'status': 'conflict',
    });
    final failure = diagnostics.conflictFailure(
      workoutId: 'instance-1',
      currentClientId: 'current-client',
    );
    expect(
      () => diagnostics.failConflict(failure, StackTrace.current),
      throwsA(same(failure)),
    );
    expect(logs.join(), contains('attemptedClientId%3Dattempted-client'));
    expect(logs.join(), contains('attemptedRevision%3D4'));
    expect(logs.join(), contains('serverRevision%3D8'));
    expect(logs.join(), contains('currentClientId%3Dcurrent-client'));
  });
}
