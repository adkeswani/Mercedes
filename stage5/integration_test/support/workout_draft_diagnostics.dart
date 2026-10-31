import 'dart:async';

class WorkoutDraftConflictFailure extends StateError {
  WorkoutDraftConflictFailure(super.message);
}

/// Browser-canary metadata only; never records draft contents or athlete IDs.
class WorkoutDraftDiagnostics {
  WorkoutDraftDiagnostics({void Function(String)? write})
      : _write = write ?? _print;

  final void Function(String) _write;
  final _elapsed = Stopwatch()..start();
  final _conflicts = <String, Map<String, Object?>>{};
  var _sequence = 0;

  static void _print(String message) {
    // ignore: avoid_print
    print(message);
  }

  void record(Map<String, Object?> event) {
    final metadata = {
      for (final key in const [
        'operation',
        'phase',
        'workoutId',
        'clientId',
        'revision',
        'serverClientId',
        'serverRevision',
        'currentClientId',
        'transactionAttempt',
        'status',
      ])
        if (event.containsKey(key)) key: event[key],
    };
    if (metadata['phase'] == 'save-result' &&
        metadata['status'] == 'conflict') {
      _conflicts[metadata['workoutId']! as String] = Map.of(metadata);
    }
    _write('BROWSER_WORKOUT_DRAFT|${{
      'sequence': ++_sequence,
      'elapsedMs': _elapsed.elapsedMilliseconds,
      ...metadata,
    }.entries.map((e) => '${e.key}=${Uri.encodeComponent('${e.value}')}').join('|')}');
  }

  WorkoutDraftConflictFailure conflictFailure({
    required String workoutId,
    required String currentClientId,
  }) {
    final conflict = _conflicts[workoutId];
    record({
      if (conflict != null) ...conflict,
      'phase': 'conflict-visible',
      'workoutId': workoutId,
      'currentClientId': currentClientId,
    });
    return WorkoutDraftConflictFailure(
      'Contested draft requires review, not a Saved fallback: '
      'workoutId=$workoutId currentClientId=$currentClientId '
      'attemptedClientId=${conflict?['clientId'] ?? '<not observed>'} '
      'attemptedRevision=${conflict?['revision'] ?? '<not observed>'} '
      'serverClientId=${conflict?['serverClientId'] ?? '<not observed>'} '
      'serverRevision=${conflict?['serverRevision'] ?? '<not observed>'}',
    );
  }

  /// Run outside waitForCondition's pump; capture cannot replace the conflict.
  Future<Never> captureAndFail(
    WorkoutDraftConflictFailure failure,
    StackTrace stack, {
    Future<void> Function()? capture,
    Duration artifactTimeout = const Duration(seconds: 2),
  }) async {
    // Emit the exact failure before even starting the optional screenshot.
    _write('BROWSER_WORKOUT_DRAFT_CONFLICT|'
        'error=${Uri.encodeComponent(failure.message)}');
    if (capture != null) {
      record({'phase': 'artifact-start'});
      try {
        await capture().timeout(artifactTimeout);
        record({'phase': 'artifact-saved'});
      } on TimeoutException {
        record({'phase': 'artifact-timeout'});
      } catch (_) {
        record({'phase': 'artifact-failed'});
      }
    }
    Error.throwWithStackTrace(failure, stack);
  }
}
