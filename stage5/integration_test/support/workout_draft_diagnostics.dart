import 'dart:math';

class WorkoutDraftConflictFailure extends StateError {
  WorkoutDraftConflictFailure(super.message);
}

/// Browser-canary metadata only; never records draft contents or athlete IDs.
class WorkoutDraftDiagnostics {
  static final executionId =
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';

  static final executionStartedAt = DateTime.now().toUtc().toIso8601String();

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
        'editorId',
        'repositoryId',
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
      'executionId': executionId,
      'executionStartedAt': executionStartedAt,
      'pageUrl':
          '${Uri.base.scheme}://${Uri.base.host}:${Uri.base.port}${Uri.base.path}',
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

  /// Failure reporting must never enter the driver screenshot protocol.
  Never failConflict(
    WorkoutDraftConflictFailure failure,
    StackTrace stack,
  ) {
    _write('BROWSER_WORKOUT_DRAFT_CONFLICT|'
        'error=${Uri.encodeComponent(failure.message)}');
    Error.throwWithStackTrace(failure, stack);
  }
}
