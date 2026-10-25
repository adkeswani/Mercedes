import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/athlete_dashboard/domain/athlete_activity_event.dart';
import 'package:stage5/features/athlete_dashboard/presentation/athlete_dashboard_providers.dart';
import 'package:stage5/features/athlete_dashboard/presentation/athlete_dashboard_view.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';

void main() {
  testWidgets(
    "defaults to All and switches to Today's Workouts, Completed, Comments, "
    'and Reactions',
    (tester) async {
      final completer = Completer<AthleteDashboardPage>();
      await _pumpDashboard(tester, load: () => completer.future);

      // All is the default selected filter, so the activity feed provider
      // is invoked immediately on first build.
      expect(
        find.byKey(const Key('athlete-dashboard-filter-all')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(
        const AthleteDashboardPage(events: [], isBounded: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('No recent activity'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('athlete-dashboard-filter-todaysWorkouts')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No workouts scheduled today'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('athlete-dashboard-filter-completed')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No completed workouts'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('athlete-dashboard-filter-comments')),
      );
      await tester.pump();
      expect(find.text('No recent comments'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('athlete-dashboard-filter-reactions')),
      );
      await tester.pump();
      expect(find.text('No recent reactions'), findsOneWidget);
    },
  );

  testWidgets('renders comment and reaction activity cards', (tester) async {
    await _pumpDashboard(
      tester,
      load: () => Future.value(
        AthleteDashboardPage(
          events: [
            AthleteCommentActivityEvent(
              id: 'comment:1',
              occurredAt: DateTime(2026, 9, 19, 9),
              workoutInstanceId: 'completed-1',
              comment: 'Felt strong today',
              authorName: 'You',
            ),
            AthleteReactionActivityEvent(
              id: 'reaction:1',
              occurredAt: DateTime(2026, 9, 19, 9, 30),
              workoutInstanceId: 'completed-1',
              reactionId: 'celebrate',
              actorName: 'Coach',
            ),
          ],
          isBounded: false,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('athlete-dashboard-filter-all')),
    );
    await tester.pumpAndSettle();

    expect(find.text('You commented'), findsOneWidget);
    expect(find.textContaining('Felt strong today'), findsOneWidget);
    expect(find.text('Coach reacted'), findsOneWidget);
  });

  testWidgets('shows an error with a working retry action', (tester) async {
    var attempts = 0;
    await _pumpDashboard(
      tester,
      load: () {
        attempts++;
        if (attempts == 1) {
          return Future.error(StateError('boom'));
        }
        return Future.value(
          const AthleteDashboardPage(events: [], isBounded: false),
        );
      },
    );

    await tester.tap(
      find.byKey(const Key('athlete-dashboard-filter-all')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load activity'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No recent activity'), findsOneWidget);
    expect(attempts, 2);
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Future<AthleteDashboardPage> Function() load,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        athleteDashboardProvider.overrideWith((ref) => load()),
        athleteScheduleProvider.overrideWith((ref, range) => Stream.value([])),
      ],
      child: const MaterialApp(
        home: Scaffold(body: AthleteDashboardView()),
      ),
    ),
  );
}
