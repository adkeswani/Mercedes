import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/browser_test_wait.dart';

void main() {
  test('post-assertion marker precedes screenshot and waits for driver ack',
      () async {
    final logs = <String>[];
    final acknowledgment = Completer<void>();
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'climbing',
      artifactPath: 'artifacts',
      currentRoute: () => '/athlete/workouts/one',
    );
    await runZoned(
      () async {
        var finished = false;
        final capture = waits.captureAfterAssertions(
          'capture completed climbing history',
          () {
            expect(logs.first, 'BROWSER_SMOKE_ASSERTIONS_PASSED:athlete');
            return acknowledgment.future;
          },
        ).then((_) => finished = true);
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        expect(logs.any((line) => line.startsWith('BROWSER_TEST_STEP_PASS')),
            isFalse);
        acknowledgment.complete();
        await capture;
        expect(finished, isTrue);
        expect(logs.last, startsWith('BROWSER_TEST_STEP_PASS'));
      },
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => logs.add(line),
      ),
    );
  });

  test('functional failure cannot emit assertion marker or request screenshot',
      () async {
    final logs = <String>[];
    final failure = StateError('functional assertion failed');
    var captureCalled = false;
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'climbing',
      artifactPath: 'artifacts',
      currentRoute: () => '/athlete/workouts/one',
    );
    await runZoned(
      () async {
        Future<void> scenario() async {
          await Future<void>.error(failure);
          await waits.captureAfterAssertions('final screenshot', () async {
            captureCalled = true;
          });
        }

        await expectLater(scenario(), throwsA(same(failure)));
      },
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => logs.add(line),
      ),
    );
    expect(captureCalled, isFalse);
    expect(logs, isEmpty);
  });

  test('post-assertion screenshot failure remains explicit', () async {
    final failure = StateError('driver screenshot failed');
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'climbing',
      artifactPath: 'artifacts',
      currentRoute: () => '/athlete/workouts/one',
    );
    await expectLater(
      waits.captureAfterAssertions(
        'final screenshot',
        () => Future<void>.error(failure),
      ),
      throwsA(same(failure)),
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

  test('runStep can rely on the scenario deadline', () async {
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'integration_test/recovery_test.dart',
      artifactPath: 'artifacts',
      currentRoute: () => '/athlete/today',
    );

    final result = await waits.runStep(
      'server draft identity',
      () async => 'client-1',
      timeout: null,
    );

    expect(result, 'client-1');
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
}
