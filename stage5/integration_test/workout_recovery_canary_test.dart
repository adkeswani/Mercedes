import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'athlete completion draft survives app recreation and clears on completion',
    (tester) async {
      await app.initializeMercedesApp();
      await tester.pumpWidget(const ProviderScope(child: MercedesApp()));

      await _waitFor(tester, find.byKey(browserSmokeLoginButtonKey));
      await tester.tap(find.byKey(browserSmokeLoginButtonKey));
      await _waitFor(tester, find.text('Today'));

      final authenticatedContext = tester.element(find.text('Today').first);
      GoRouter.of(authenticatedContext).go(
        '/athlete/workouts/browser-calendar-workout',
      );
      await _waitFor(tester, find.text('Mark as Completed'));

      tester.widget<Slider>(find.byType(Slider)).onChanged!(8);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.enterText(
        find.byType(TextField),
        'Recovered after browser eviction',
      );
      await _waitFor(tester, find.text('Saving...'));
      await _waitFor(tester, find.text('Saved'));
      await binding.takeScreenshot('athlete-workout-recovery-saved');

      await tester.pumpWidget(const ProviderScope(child: MercedesApp()));
      await _waitFor(tester, find.text('Mark as Completed'));

      final restoredContext =
          tester.element(find.text('Mark as Completed').first);
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
      await binding.takeScreenshot('athlete-workout-recovery-restored');

      await tester.tap(find.text('Mark as Completed'));
      await _waitFor(tester, find.text('Workout completed! 💪'));
      final draft = await FirebaseFirestore.instance
          .collection('workoutInstances')
          .doc('browser-calendar-workout')
          .collection('completionDrafts')
          .doc('current')
          .get();
      expect(draft.exists, isFalse);
      await binding.takeScreenshot('athlete-workout-recovery-completed');
    },
    skip: browserSmokeConfig.identityRole != BrowserSmokeIdentityRole.athlete,
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsAtLeastNWidgets(1));
}
