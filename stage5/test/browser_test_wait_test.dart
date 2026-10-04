import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/browser_test_wait.dart';

void main() {
  test('startup and functional pumps have distinct bounded defaults', () {
    expect(
      BrowserTestWaitContext.startupFirstFramePumpTimeout,
      const Duration(seconds: 15),
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

  test('startup separates synchronous root attachment from first-frame polls',
      () async {
    var attached = false;
    var pumpCalls = 0;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/login',
    );

    await waits.attachRootAndWaitForCondition(
      attachStep: 'attach initial application root',
      attachRoot: () {
        attached = true;
      },
      condition: 'local emulator login button',
      isSatisfied: () => pumpCalls == 3,
      pump: () async {
        pumpCalls++;
      },
      startupTimeout: const Duration(milliseconds: 100),
      firstFramePumpTimeout: const Duration(milliseconds: 5),
    );

    expect(attached, isTrue);
    expect(pumpCalls, 3);
  });

  test('non-cancellable startup pump reports the named sub-deadline', () async {
    var attachCalls = 0;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/login',
    );

    await expectLater(
      waits.attachRootAndWaitForCondition(
        attachStep: 'attach initial application root',
        attachRoot: () {
          attachCalls++;
        },
        condition: 'local emulator login button',
        isSatisfied: () => false,
        pump: () => Completer<void>().future,
        startupTimeout: const Duration(milliseconds: 100),
        firstFramePumpTimeout: const Duration(milliseconds: 10),
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
    expect(attachCalls, 1);
  });

  test('startup surfaces framework errors before polling', () async {
    var pumpCalls = 0;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '<application not mounted>',
    );

    await expectLater(
      waits.attachRootAndWaitForCondition(
        attachStep: 'attach initial application root',
        attachRoot: () {},
        condition: 'local emulator login button',
        isSatisfied: () => false,
        pump: () async {
          pumpCalls++;
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
    expect(pumpCalls, 0);
  });

  test('startup prefers a captured framework error over pump timeout',
      () async {
    var pumpStarted = false;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '<application not mounted>',
    );

    await expectLater(
      waits.attachRootAndWaitForCondition(
        attachStep: 'attach initial application root',
        attachRoot: () {},
        condition: 'local emulator login button',
        isSatisfied: () => false,
        pump: () {
          pumpStarted = true;
          return Completer<void>().future;
        },
        takeFrameworkException: () =>
            pumpStarted ? StateError('Firebase provider build failed') : null,
        startupTimeout: const Duration(milliseconds: 100),
        firstFramePumpTimeout: const Duration(milliseconds: 10),
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

  test('startup pump can outlive the later functional pump bound', () async {
    var startupReady = false;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/login',
    );

    Future<void> delayedPump(void Function() onComplete) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      onComplete();
    }

    await waits.attachRootAndWaitForCondition(
      attachStep: 'attach initial application root',
      attachRoot: () {},
      condition: 'local emulator login button',
      isSatisfied: () => startupReady,
      pump: () => delayedPump(() => startupReady = true),
      startupTimeout: const Duration(milliseconds: 100),
      firstFramePumpTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      waits.waitForCondition(
        condition: 'later functional surface',
        isSatisfied: () => false,
        pump: () => delayedPump(() {}),
        timeout: const Duration(milliseconds: 100),
        pumpTimeout: const Duration(milliseconds: 5),
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

  testWidgets('binding root attachment completes before first-frame polling',
      (tester) async {
    var attachReturned = false;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '<first frame pending>',
    );

    await waits.attachRootAndWaitForCondition(
      attachStep: 'attach initial application root',
      attachRoot: () {
        tester.binding.attachRootWidget(
          tester.binding.wrapWithDefaultView(
            const MaterialApp(home: Text('Login ready')),
          ),
        );
        tester.binding.scheduleFrame();
        attachReturned = true;
      },
      condition: 'local emulator login button',
      isSatisfied: () => find.text('Login ready').evaluate().isNotEmpty,
      pump: () => tester.pump(const Duration(milliseconds: 1)),
      takeFrameworkException: tester.takeException,
      startupTimeout: const Duration(seconds: 1),
    );

    expect(attachReturned, isTrue);
    expect(find.text('Login ready'), findsOneWidget);
  });
}
