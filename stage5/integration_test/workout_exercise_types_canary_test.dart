import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/main.dart' as app;

import 'support/browser_test_wait.dart';

const _testFile = 'integration_test/workout_exercise_types_canary_test.dart';
const _artifactPath = String.fromEnvironment(
  'BROWSER_TEST_ARTIFACT_PATH',
  defaultValue: '<not provided>',
);

/// Deterministic workout seeded by tool/run-browser-login-smoke.ps1 with
/// one block of each exercise type: standard (reps/sets/weight), timed
/// (duration), and climbing route (attempts/sent).
const _workoutInstanceId = 'browser-exercise-types-workout';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'athlete fills in and completes a workout covering all exercise types',
    (tester) async {
      final waits = BrowserTestWaitContext(
        identity: browserSmokeConfig.identityRole?.name ?? 'unconfigured',
        testFile: _testFile,
        artifactPath: _artifactPath,
        currentRoute: () => _currentRoute(tester),
      );
      await waits.runStep(
        'initialize Firebase emulators',
        app.initializeMercedesApp,
        timeout: const Duration(seconds: 30),
      );
      await waits.runStep(
        'pump initial application',
        () => tester.pumpWidget(
          const ProviderScope(child: MercedesApp()),
        ),
      );

      await _waitFor(
        tester,
        waits,
        find.byKey(browserSmokeLoginButtonKey),
        step: 'local emulator login button',
      );
      await waits.runStep(
        'submit local emulator login',
        () => tester.tap(find.byKey(browserSmokeLoginButtonKey)),
      );
      await _waitFor(
        tester,
        waits,
        find.byKey(authenticatedAppEntryKey),
        step: 'authenticated athlete workspace',
        timeout: const Duration(seconds: 30),
      );

      final appContext = tester.element(find.byKey(authenticatedAppEntryKey));
      GoRouter.of(appContext).go(
        '/athlete/workouts/$_workoutInstanceId',
      );
      await _waitFor(
        tester,
        waits,
        find.text('Complete Workout'),
        step: 'exercise-types workout completion screen',
        timeout: const Duration(seconds: 30),
      );

      // Standard exercise: sets/reps/weight fields, visible without
      // scrolling since it is the first card.
      await _waitFor(
        tester,
        waits,
        find.text('Browser Trainer Exercise'),
        step: 'standard exercise card',
      );
      await waits.runStep(
        'enter standard exercise actuals',
        () async {
          await tester.enterText(
            find.widgetWithText(TextField, 'Sets'),
            '3',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Reps'),
            '10',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Weight'),
            '20kg',
          );
        },
      );

      // Timed exercise: duration-in-seconds field.
      await waits.runStep(
        'scroll to timed exercise card',
        () => tester.scrollUntilVisible(
          find.text('Plank Hold'),
          300,
          scrollable: find.byType(Scrollable).first,
        ),
      );
      await waits.runStep(
        'enter timed exercise actual',
        () => tester.enterText(
          find.widgetWithText(TextField, 'Duration (seconds)'),
          '35',
        ),
      );

      // Climbing route: attempts field plus a "sent the route" checkbox.
      await waits.runStep(
        'scroll to climbing exercise card',
        () => tester.scrollUntilVisible(
          find.text('Boulder Problem'),
          300,
          scrollable: find.byType(Scrollable).first,
        ),
      );
      await waits.runStep(
        'enter climbing exercise actuals',
        () async {
          await tester.enterText(
            find.widgetWithText(TextField, 'Attempts'),
            '4',
          );
          await tester.scrollUntilVisible(
            find.byType(Checkbox),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(Checkbox));
          await tester.pump();
        },
      );

      await waits.runStep(
        'reveal completion controls',
        () => tester.scrollUntilVisible(
          find.text('Mark as Completed'),
          300,
          scrollable: find.byType(Scrollable).first,
        ),
      );
      await waits.runStep(
        'submit workout completion',
        () => tester.tap(find.text('Mark as Completed')),
      );
      await _waitForAbsent(
        tester,
        waits,
        find.text('Complete Workout'),
        step: 'completed workout navigation',
        timeout: const Duration(seconds: 30),
      );
      expect(
        find.textContaining('permission'),
        findsNothing,
        reason: 'A permission-denied error indicates the completion '
            'workflow regressed.',
      );

      final slotResults = await waits.runStep(
        'verify slot results in Firestore',
        () => FirebaseFirestore.instance
            .collection('workoutInstances')
            .doc(_workoutInstanceId)
            .collection('slotResults')
            .get(),
      );
      final bySlotId = {
        for (final doc in slotResults.docs) doc.id: doc.data(),
      };
      expect(
        bySlotId.keys,
        containsAll(<String>[
          'slot-standard',
          'slot-timed',
          'slot-climbing',
        ]),
      );
      expect(bySlotId['slot-standard']?['sets'], 3);
      expect(bySlotId['slot-standard']?['reps'], '10');
      expect(bySlotId['slot-standard']?['weight'], '20kg');
      expect(bySlotId['slot-timed']?['durationSeconds'], 35);
      expect(bySlotId['slot-climbing']?['attempts'], 4);
      expect(bySlotId['slot-climbing']?['sent'], isTrue);

      final instance = await waits.runStep(
        'verify workout instance marked completed',
        () => FirebaseFirestore.instance
            .collection('workoutInstances')
            .doc(_workoutInstanceId)
            .get(),
      );
      expect(instance.data()?['status'], 'completed');
    },
    skip: browserSmokeConfig.identityRole != BrowserSmokeIdentityRole.athlete,
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  BrowserTestWaitContext waits,
  Finder finder, {
  required String step,
  Duration timeout = const Duration(seconds: 20),
}) {
  return waits.waitForCondition(
    condition: step,
    isSatisfied: () => finder.evaluate().isNotEmpty,
    pump: () => tester.pump(const Duration(milliseconds: 100)),
    timeout: timeout,
    details: () => 'Visible text: ${_visibleText()}',
  );
}

Future<void> _waitForAbsent(
  WidgetTester tester,
  BrowserTestWaitContext waits,
  Finder finder, {
  required String step,
  Duration timeout = const Duration(seconds: 20),
}) {
  return waits.waitForCondition(
    condition: step,
    isSatisfied: () => finder.evaluate().isEmpty,
    pump: () => tester.pump(const Duration(milliseconds: 100)),
    timeout: timeout,
    details: () => 'Visible text: ${_visibleText()}',
  );
}

String _visibleText() {
  return find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .where((text) => text.isNotEmpty)
      .take(20)
      .join(' | ');
}

String _currentRoute(WidgetTester tester) {
  final navigators = find.byType(Navigator);
  if (navigators.evaluate().isEmpty) {
    return '<application not mounted>';
  }
  return GoRouter.of(
    tester.element(navigators.first),
  ).routeInformationProvider.value.uri.toString();
}
