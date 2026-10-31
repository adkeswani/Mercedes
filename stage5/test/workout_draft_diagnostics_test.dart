import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/browser_test_wait.dart';
import '../integration_test/support/workout_draft_diagnostics.dart';

void main() {
  test('writer events contain only allowlisted metadata in sequence', () {
    final logs = <String>[];
    final diagnostics = WorkoutDraftDiagnostics(write: logs.add);
    diagnostics.record({
      'operation': 1,
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
    expect(logs.last, contains('sequence=2'));
    expect(logs.join(), isNot(contains('PRIVATE')));
    expect(logs.join(), isNot(contains('notes')));
  });

  test('conflict capture runs outside the bounded Flutter pump', () async {
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
    Future<void> waitAndCapture() async {
      try {
        await waits.waitForCondition(
          condition: 'save settled before RPE',
          isSatisfied: () => false,
          pump: () async => throw failure,
          pumpTimeout: const Duration(milliseconds: 1),
        );
      } on WorkoutDraftConflictFailure catch (error, stack) {
        await diagnostics.captureAndFail(
          error,
          stack,
          capture: () => Completer<void>().future,
          artifactTimeout: const Duration(milliseconds: 10),
        );
      }
    }

    await expectLater(waitAndCapture(), throwsA(same(failure)));
    expect(logs.last, contains('phase=artifact-timeout'));
    expect(failure.message, contains('attemptedRevision=<not observed>'));
  });

  for (final outcome in ['delayed', 'failed', 'successful']) {
    test('logs conflict before $outcome screenshot and preserves failure',
        () async {
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
      final elapsed = Stopwatch()..start();
      final waits = BrowserTestWaitContext(
        identity: 'athlete',
        testFile: 'climbing',
        artifactPath: 'artifacts',
        currentRoute: () => '/athlete/workouts/instance-1',
      );
      await expectLater(
        waits.runStep(
          'supplementary conflict screenshot',
          () => diagnostics.captureAndFail(
            failure,
            StackTrace.current,
            artifactTimeout: const Duration(milliseconds: 10),
            capture: () {
              expect(logs.join(),
                  contains('attemptedClientId%3Dattempted-client'));
              expect(logs.join(), contains('attemptedRevision%3D4'));
              expect(logs.join(), contains('serverRevision%3D8'));
              expect(logs.join(), contains('currentClientId%3Dcurrent-client'));
              if (outcome == 'delayed') return Completer<void>().future;
              if (outcome == 'failed') {
                return Future.error(StateError('PRIVATE CAPTURE ERROR'));
              }
              return Future.value();
            },
          ),
          timeout: const Duration(seconds: 1),
        ),
        throwsA(same(failure)),
      );
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
      expect(logs.join(), isNot(contains('PRIVATE CAPTURE ERROR')));
      expect(
          logs.last,
          contains('phase=artifact-${{
            'delayed': 'timeout',
            'failed': 'failed',
            'successful': 'saved',
          }[outcome]}'));
    });
  }
}
