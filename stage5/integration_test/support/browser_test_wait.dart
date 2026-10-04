import 'dart:async';

typedef BrowserTestRouteReader = String Function();
typedef BrowserTestDelay = Future<void> Function(Duration duration);

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

  static const functionalPumpTimeout = Duration(seconds: 2);
  static const startupPollInterval = Duration(milliseconds: 100);

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
    Duration pumpTimeout = functionalPumpTimeout,
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

  Future<void> attachRootAndWaitForLiveCondition({
    required String attachStep,
    required void Function() attachRoot,
    required String condition,
    required bool Function() isSatisfied,
    Object? Function()? takeFrameworkException,
    Duration startupTimeout = const Duration(seconds: 30),
    Duration pollInterval = startupPollInterval,
    BrowserTestDelay delay = Future<void>.delayed,
    String Function()? details,
  }) async {
    final stopwatch = Stopwatch()..start();
    var activeStep = attachStep;
    _writeProgress('START', attachStep, stopwatch.elapsed);
    try {
      attachRoot();
      _throwFrameworkException(
        step: attachStep,
        takeFrameworkException: takeFrameworkException,
      );
      _writeProgress('PASS', attachStep, stopwatch.elapsed);
      activeStep = condition;
      _writeProgress('START', condition, stopwatch.elapsed);
      while (!isSatisfied() && stopwatch.elapsed < startupTimeout) {
        _throwFrameworkException(
          step: condition,
          takeFrameworkException: takeFrameworkException,
        );
        final remaining = startupTimeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          break;
        }
        final currentDelay =
            remaining < pollInterval ? remaining : pollInterval;
        await delay(currentDelay);
        _throwFrameworkException(
          step: condition,
          takeFrameworkException: takeFrameworkException,
        );
      }
      if (!isSatisfied()) {
        final suffix = details == null ? '' : ' Details: ${details()}';
        throw TimeoutException(
          '${_timeoutMessage(
            condition,
            startupTimeout,
            stopwatch.elapsed,
          )}$suffix',
        );
      }
      _writeProgress('PASS', condition, stopwatch.elapsed);
    } catch (error) {
      final frameworkError = takeFrameworkException?.call();
      if (frameworkError != null) {
        final reported = StateError(
          'Flutter framework error during $activeStep: $frameworkError',
        );
        _writeProgress(
          'FAIL',
          activeStep,
          stopwatch.elapsed,
          error: reported,
        );
        throw reported;
      }
      _writeProgress('FAIL', activeStep, stopwatch.elapsed, error: error);
      rethrow;
    }
  }

  void _throwFrameworkException({
    required String step,
    required Object? Function()? takeFrameworkException,
  }) {
    final error = takeFrameworkException?.call();
    if (error != null) {
      throw StateError('Flutter framework error during $step: $error');
    }
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
