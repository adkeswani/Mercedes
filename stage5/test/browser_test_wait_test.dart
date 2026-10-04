import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/browser_test_wait.dart';

void main() {
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

  test('startup mount uses the startup budget, not the pump sub-deadline',
      () async {
    var mounted = false;
    var pumpCalls = 0;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/login',
    );

    await waits.mountAndWaitForCondition(
      mountStep: 'pump initial application',
      mount: () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        mounted = true;
      },
      condition: 'local emulator login button',
      isSatisfied: () => mounted,
      pump: () async {
        pumpCalls++;
      },
      startupTimeout: const Duration(milliseconds: 100),
      pumpTimeout: const Duration(milliseconds: 5),
    );

    expect(mounted, isTrue);
    expect(pumpCalls, 0);
  });

  test('startup polling reports the named pump sub-deadline', () async {
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/login',
    );

    await expectLater(
      waits.mountAndWaitForCondition(
        mountStep: 'pump initial application',
        mount: () async {},
        condition: 'local emulator login button',
        isSatisfied: () => false,
        pump: () => Completer<void>().future,
        startupTimeout: const Duration(milliseconds: 100),
        pumpTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<TimeoutException>()
            .having(
              (error) => error.message,
              'message',
              contains('local emulator login button'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('Flutter pump stalled'),
            ),
      ),
    );
  });

  test('startup mount timeout retains the mount step name', () async {
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '<application not mounted>',
    );

    await expectLater(
      waits.mountAndWaitForCondition(
        mountStep: 'pump initial application',
        mount: () => Completer<void>().future,
        condition: 'local emulator login button',
        isSatisfied: () => false,
        pump: () async {},
        startupTimeout: const Duration(milliseconds: 10),
        pumpTimeout: const Duration(milliseconds: 2),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('pump initial application'),
            contains('<application not mounted>'),
          ),
        ),
      ),
    );
  });
}
