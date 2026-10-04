import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/browser_test_wait.dart';

void main() {
  test('startup observation and functional pumps have bounded defaults', () {
    expect(
      BrowserTestWaitContext.startupPollInterval,
      const Duration(milliseconds: 100),
    );
    expect(
      BrowserTestWaitContext.functionalPumpTimeout,
      const Duration(seconds: 2),
    );
  });

  test('runStep reports bounded diagnostic context', () async {
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: r'C:\artifacts\run-1',
      currentRoute: () => '/athlete/workouts/instance-1',
    );

    await expectLater(
      waits.runStep<void>(
        'server draft deletion',
        () => Completer<void>().future,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<TimeoutException>()
            .having(
              (error) => error.message,
              'message',
              contains('Identity: athlete'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('integration_test/recovery_test.dart'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('/athlete/workouts/instance-1'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('server draft deletion'),
            )
            .having(
              (error) => error.message,
              'message',
              contains(r'C:\artifacts\run-1'),
            ),
      ),
    );
  });

  test('waitForCondition stops polling when the condition succeeds', () async {
    var polls = 0;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/athlete/today',
    );

    await waits.waitForCondition(
      condition: 'saved indicator',
      isSatisfied: () => polls >= 3,
      pump: () async {
        polls++;
      },
      timeout: const Duration(seconds: 1),
    );

    expect(polls, 3);
  });

  test('waitForCondition bounds a stalled pump', () async {
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/athlete/today',
    );

    await expectLater(
      waits.waitForCondition(
        condition: 'authenticated workspace',
        isSatisfied: () => false,
        pump: () => Completer<void>().future,
        timeout: const Duration(seconds: 1),
        pumpTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('Flutter pump stalled'),
        ),
      ),
    );
  });

  test('startup separates root attachment from live-engine observation',
      () async {
    var attached = false;
    var polls = 0;
    var ready = false;
    var legacyPumpInvoked = false;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/login',
    );

    Future<void> neverCompletingPump() {
      legacyPumpInvoked = true;
      return Completer<void>().future;
    }

    await waits.attachRootAndWaitForLiveCondition(
      attachStep: 'attach initial application root',
      attachRoot: () {
        attached = true;
      },
      condition: 'local emulator login button',
      isSatisfied: () => ready,
      delay: (_) async {
        polls++;
        ready = polls == 3;
      },
      startupTimeout: const Duration(milliseconds: 100),
    );

    expect(neverCompletingPump, isA<Future<void> Function()>());
    expect(attached, isTrue);
    expect(polls, 3);
    expect(legacyPumpInvoked, isFalse);
  });

  test('startup surfaces framework errors before live observation', () async {
    var delayCalls = 0;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '<application not mounted>',
    );

    await expectLater(
      waits.attachRootAndWaitForLiveCondition(
        attachStep: 'attach initial application root',
        attachRoot: () {},
        condition: 'local emulator login button',
        isSatisfied: () => false,
        delay: (_) async {
          delayCalls++;
        },
        takeFrameworkException: () => StateError('router build failed'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('attach initial application root'),
            contains('router build failed'),
          ),
        ),
      ),
    );
    expect(delayCalls, 0);
  });

  test('startup captures framework errors during live observation', () async {
    var delayed = false;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '<application not mounted>',
    );

    await expectLater(
      waits.attachRootAndWaitForLiveCondition(
        attachStep: 'attach initial application root',
        attachRoot: () {},
        condition: 'local emulator login button',
        isSatisfied: () => false,
        delay: (_) async {
          delayed = true;
        },
        takeFrameworkException: () =>
            delayed ? StateError('Firebase provider build failed') : null,
        startupTimeout: const Duration(milliseconds: 100),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('local emulator login button'),
            contains('Firebase provider build failed'),
          ),
        ),
      ),
    );
  });

  test('later functional polling still guards a non-cancellable pump',
      () async {
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/athlete/today',
    );

    await expectLater(
      waits.waitForCondition(
        condition: 'later functional surface',
        isSatisfied: () => false,
        pump: () => Completer<void>().future,
        timeout: const Duration(milliseconds: 100),
        pumpTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('Flutter pump stalled'),
        ),
      ),
    );
  });
}
