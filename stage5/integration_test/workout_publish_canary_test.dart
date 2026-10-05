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

const _testFile = 'integration_test/workout_publish_canary_test.dart';
const _artifactPath = String.fromEnvironment(
  'BROWSER_TEST_ARTIFACT_PATH',
  defaultValue: '<not provided>',
);

/// Deterministic trainer exercise seeded by
/// tool/run-browser-login-smoke.ps1 with currentVersion: 1.
const _seededExerciseName = 'Browser Trainer Exercise';

const _newWorkoutName = 'Browser Publish Canary Workout';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'trainer publishes a brand-new single-exercise workout (happy path)',
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
        step: 'authenticated trainer workspace',
        timeout: const Duration(seconds: 30),
      );

      // Regression coverage for: a brand-new workout's very first publish
      // used to fail with "Missing or insufficient permissions" because the
      // workoutTemplateVersions read rule dereferenced resource.data for a
      // version document that had never been created yet. This test drives
      // the exact UI path a trainer uses: create a new workout, add one
      // (pre-existing) exercise, and publish for the first time.
      final appContext = tester.element(find.byKey(authenticatedAppEntryKey));
      GoRouter.of(appContext).go('/workouts/new');
      await _waitFor(
        tester,
        waits,
        find.text('New Workout Template'),
        step: 'new workout creation form',
        timeout: const Duration(seconds: 20),
      );

      await waits.runStep(
        'enter new workout name',
        () => tester.enterText(
          find.widgetWithText(TextField, 'Workout Name'),
          _newWorkoutName,
        ),
      );
      await waits.runStep(
        'create workout and enter builder',
        () => tester.tap(find.text('Create & Start Building')),
      );
      await _waitFor(
        tester,
        waits,
        find.text('Publish'),
        step: 'workout builder screen for new workout',
        timeout: const Duration(seconds: 20),
      );

      await waits.runStep(
        'open exercise picker',
        () => tester.tap(find.text('Add')),
      );
      await _waitFor(
        tester,
        waits,
        find.text(_seededExerciseName),
        step: 'seeded exercise visible in picker',
        timeout: const Duration(seconds: 20),
      );
      await waits.runStep(
        'select seeded exercise',
        () => tester.tap(find.text(_seededExerciseName).last),
      );
      await _waitFor(
        tester,
        waits,
        find.text(_seededExerciseName),
        step: 'exercise added to draft',
        timeout: const Duration(seconds: 20),
      );
      // The exercise picker's modal bottom sheet is still mid dismiss
      // animation at this point: Navigator.pop() resolves (and the parent
      // setState adds the slot to the draft, satisfying the wait above)
      // before the sheet's exit transition finishes. Its scrim/overlay can
      // still intercept the very next tap, so let it fully settle before
      // interacting with the AppBar again.
      await waits.runStep(
        'settle exercise picker dismiss animation',
        () => tester.pumpAndSettle(),
      );

      await waits.runStep(
        'publish the new workout',
        () => tester.tap(find.text('Publish')),
      );
      await _waitFor(
        tester,
        waits,
        find.text('Published version 1'),
        step: 'publish success snackbar (no permission error)',
        timeout: const Duration(seconds: 20),
      );
      expect(
        find.textContaining('permission'),
        findsNothing,
        reason: 'A permission-denied error indicates the publish regression '
            'has returned.',
      );

      final workoutId = Uri.parse(_currentRoute(tester)).pathSegments.last;
      final header = await waits.runStep(
        'verify published header in Firestore',
        () => FirebaseFirestore.instance
            .collection('workoutTemplates')
            .doc(workoutId)
            .get(),
      );
      expect(header.data()?['currentVersion'], 1);

      final version = await waits.runStep(
        'verify published version document in Firestore',
        () => FirebaseFirestore.instance
            .collection('workoutTemplates')
            .doc(workoutId)
            .collection('workoutTemplateVersions')
            .doc('1')
            .get(),
      );
      expect(version.exists, isTrue);
      expect(version.data()?['publishState'], 'published');
    },
    skip: browserSmokeConfig.identityRole != BrowserSmokeIdentityRole.trainer,
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
