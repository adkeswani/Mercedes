import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/main.dart' as app;

import 'support/browser_test_wait.dart';

const _testFile = 'integration_test/program_assignment_canary_test.dart';
const _artifactPath = String.fromEnvironment(
  'BROWSER_TEST_ARTIFACT_PATH',
  defaultValue: '<not provided>',
);

/// Deterministic assignable program and athlete seeded by
/// tool/run-browser-login-smoke.ps1.
const _seededProgramId = 'browser-athlete-program';
const _seededAthleteUsername = 'browser_smoke_athlete';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'trainer assigns a program to an athlete for the first time (happy path)',
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

      // Regression coverage for: assigning a program to an enrolled athlete
      // used to fail on the very first attempt with "Missing or insufficient
      // permissions" because the athleteProgramInstances get rule
      // dereferenced resource.data for the brand-new instance id that
      // WorkoutInstanceRepository.assignProgram() always checks for a prior
      // idempotent assignment before writing anything. This test drives the
      // exact repository call a trainer's "Assign Program" action makes.
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(authenticatedAppEntryKey)),
      );
      final trainerUid = container.read(authStateProvider).value?.uid;
      expect(
        trainerUid,
        isNotNull,
        reason: 'Trainer must be signed in before assigning a program.',
      );
      final athleteProfile = await waits.runStep(
        'look up deterministic athlete profile',
        () => container
            .read(userProfileRepositoryProvider)
            .getUserByUsername(_seededAthleteUsername),
      );
      expect(
        athleteProfile,
        isNotNull,
        reason: 'Seeded athlete profile must exist for this canary.',
      );
      final athleteUid = athleteProfile!.uid;

      final startDate = DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String()
          .split('T')
          .first;

      final appContext = tester.element(find.byKey(authenticatedAppEntryKey));
      GoRouter.of(appContext).push(
        '/assign?programId=$_seededProgramId&athleteId=$athleteUid'
        '&mode=program&date=$startDate',
      );
      await _waitFor(
        tester,
        waits,
        find.text('Assign Program'),
        step: 'program assignment screen (fixed program and athlete)',
        timeout: const Duration(seconds: 20),
      );

      await waits.runStep(
        'submit program assignment',
        () => tester.tap(find.text('Assign Program')),
      );
      await _waitFor(
        tester,
        waits,
        find.textContaining('Assigned'),
        step: 'assignment success snackbar (no permission error)',
        timeout: const Duration(seconds: 20),
      );
      expect(
        find.textContaining('permission'),
        findsNothing,
        reason: 'A permission-denied error indicates the assignment '
            'regression has returned.',
      );

      final matches = await waits.runStep(
        'verify athlete program instance created in Firestore',
        () => FirebaseFirestore.instance
            .collection('athleteProgramInstances')
            .where('assigningTrainerId', isEqualTo: trainerUid)
            .where('status', isEqualTo: 'active')
            .where('sourceProgramId', isEqualTo: _seededProgramId)
            .limit(10)
            .get(),
      );
      final created = matches.docs.where(
        (doc) =>
            doc.data()['athleteOwnerId'] == athleteUid &&
            doc.data()['startDate'] == startDate,
      );
      expect(
        created,
        isNotEmpty,
        reason: 'assignProgram() should have created a new instance doc.',
      );
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
