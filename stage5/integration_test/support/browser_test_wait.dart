import 'dart:async';

typedef BrowserTestRouteReader = String Function();

class BrowserTestWaitContext {
  BrowserTestWaitContext({
    required this.identity,
    required this.testFile,
    required this.artifactPath,
    required this.currentRoute,
  });

  final String identity;
  final String testFile;
  final String artifactPath;
  final BrowserTestRouteReader currentRoute;

  Future<T> runStep<T>(
    String condition,
    Future<T> Function() operation, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final stopwatch = Stopwatch()..start();
    _writeProgress('START', condition, stopwatch.elapsed);
    try {
      final result = await operation().timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          _timeoutMessage(condition, timeout, stopwatch.elapsed),
        ),
      );
      _writeProgress('PASS', condition, stopwatch.elapsed);
      return result;
    } catch (error) {
      _writeProgress('FAIL', condition, stopwatch.elapsed, error: error);
      rethrow;
    }
  }

  Future<void> waitForCondition({
    required String condition,
    required bool Function() isSatisfied,
    required Future<void> Function() pump,
    Duration timeout = const Duration(seconds: 20),
    Duration pumpTimeout = const Duration(seconds: 2),
    String Function()? details,
  }) async {
    final stopwatch = Stopwatch()..start();
    _writeProgress('START', condition, stopwatch.elapsed);
    while (!isSatisfied() && stopwatch.elapsed < timeout) {
      try {
        await pump().timeout(
          pumpTimeout,
          onTimeout: () => throw TimeoutException(
            _timeoutMessage(
              '$condition (Flutter pump stalled)',
              pumpTimeout,
              stopwatch.elapsed,
            ),
          ),
        );
      } catch (error) {
        _writeProgress('FAIL', condition, stopwatch.elapsed, error: error);
        rethrow;
      }
    }
    if (!isSatisfied()) {
      final suffix = details == null ? '' : ' Details: ${details()}';
      final error = TimeoutException(
        '${_timeoutMessage(condition, timeout, stopwatch.elapsed)}$suffix',
      );
      _writeProgress('FAIL', condition, stopwatch.elapsed, error: error);
      throw error;
    }
    _writeProgress('PASS', condition, stopwatch.elapsed);
  }

  String _timeoutMessage(
    String condition,
    Duration timeout,
    Duration elapsed,
  ) {
    return 'Browser test timed out after ${timeout.inSeconds}s '
        '(elapsed ${elapsed.inMilliseconds}ms). '
        'Identity: $identity. Test file: $testFile. '
        'Current route: ${_safeCurrentRoute()}. '
        'Awaited condition: $condition. Artifact path: $artifactPath.';
  }

  void _writeProgress(
    String state,
    String condition,
    Duration elapsed, {
    Object? error,
  }) {
    final fields = <String, String>{
      'identity': identity,
      'file': testFile,
      'condition': condition,
      'route': _safeCurrentRoute(),
      'elapsedMs': '${elapsed.inMilliseconds}',
      'artifact': artifactPath,
      if (error != null) 'error': '$error',
    };
    final serialized = fields.entries
        .map(
          (entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}',
        )
        .join('|');
    // Parsed by scripts/run-stage-validation.ps1 for its scenario deadline.
    // ignore: avoid_print
    print('BROWSER_TEST_STEP_$state|$serialized');
  }

  String _safeCurrentRoute() {
    try {
      return currentRoute();
    } catch (_) {
      return '<unavailable>';
    }
  }
}
