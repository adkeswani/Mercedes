import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/main.dart' as app;

import 'support/browser_test_wait.dart';

const _testFile = 'integration_test/workout_recovery_canary_test.dart';
const _artifactPath = String.fromEnvironment(
  'BROWSER_TEST_ARTIFACT_PATH',
  defaultValue: '<not provided>',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'athlete completion draft survives app recreation and clears on completion',
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
        find.text('Today'),
        step: 'authenticated athlete workspace',
        timeout: const Duration(seconds: 30),
      );

      final authenticatedContext = tester.element(find.text('Today').first);
      GoRouter.of(authenticatedContext).go(
        '/athlete/workouts/browser-calendar-workout',
      );
      await _waitFor(
        tester,
        waits,
        find.text('Complete Workout'),
        step: 'canonical workout route',
      );
      final initialClientId = ProviderScope.containerOf(
        tester.element(find.byType(MercedesApp)),
      ).read(workoutDraftClientIdProvider);

      tester.widget<Slider>(find.byType(Slider)).onChanged!(8);
      await waits.runStep(
        'increase duration',
        () => tester.tap(find.byIcon(Icons.add_circle_outline)),
      );
      await waits.runStep(
        'enter athlete notes',
        () => tester.enterText(
          find.byType(TextField),
          'Recovered after browser eviction',
        ),
      );
      await _waitFor(
        tester,
        waits,
        find.text('Saving...'),
        step: 'draft saving indicator',
      );
      await _waitFor(
        tester,
        waits,
        find.text('Saved'),
        step: 'draft saved indicator',
      );
      await waits.runStep('verify initial draft client identity', () async {
        final savedDraft = await FirebaseFirestore.instance
            .collection('workoutInstances')
            .doc('browser-calendar-workout')
            .collection('completionDrafts')
            .doc('current')
            .get();
        expect(savedDraft.data()?['clientId'], initialClientId);
      });

      final workoutContext = tester.element(find.text('Complete Workout'));
      GoRouter.of(workoutContext).go('/athlete/today');
      await _waitFor(
        tester,
        waits,
        find.text('Today'),
        step: 'navigate away from workout',
      );
      await _waitForAbsent(
        tester,
        waits,
        find.text('Complete Workout'),
        step: 'dispose workout screen',
      );

      final recreatedClientId = ProviderScope.containerOf(
        tester.element(find.byType(MercedesApp)),
      ).read(workoutDraftClientIdProvider);
      expect(
        recreatedClientId,
        initialClientId,
        reason: 'Screen recreation must retain the current tab client ID.',
      );
      final athleteContext = tester.element(find.text('Today').first);
      GoRouter.of(athleteContext).go(
        '/athlete/workouts/browser-calendar-workout',
      );
      await _waitFor(
        tester,
        waits,
        find.text('Complete Workout'),
        step: 'restored canonical workout route',
        timeout: const Duration(seconds: 30),
      );
      final restoredContext = tester.element(find.text('Complete Workout'));
      expect(
        GoRouter.of(
          restoredContext,
        ).routeInformationProvider.value.uri.path,
        '/athlete/workouts/browser-calendar-workout',
      );
      expect(find.text('8'), findsOneWidget);
      expect(find.text('50 min'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Recovered after browser eviction',
      );
      expect(
        find.textContaining('Restored saved workout progress'),
        findsOneWidget,
      );
      await waits.runStep(
        'reveal restored completion controls',
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
      final draft = await waits.runStep(
        'verify server draft deletion',
        () => FirebaseFirestore.instance
            .collection('workoutInstances')
            .doc('browser-calendar-workout')
            .collection('completionDrafts')
            .doc('current')
            .get(),
      );
      expect(draft.exists, isFalse);
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
