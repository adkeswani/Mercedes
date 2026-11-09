import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/features/athlete_dashboard/domain/athlete_activity_event.dart';
import 'package:stage5/features/athlete_dashboard/presentation/athlete_dashboard_providers.dart';
import 'package:stage5/features/athlete_dashboard/presentation/athlete_dashboard_view.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  for (final started in [false, true]) {
    testWidgets('${started ? 'Continue' : 'Begin'} opens the same workout',
        (tester) async {
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: AthleteDashboardView()),
          ),
        ),
        GoRoute(
          path: '/athlete/workouts/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Workout ${state.pathParameters['id']}')),
        ),
      ]);
      addTearDown(router.dispose);
      await _pumpDashboard(
        tester,
        router: router,
        schedule: (_) => Stream.value([_todayWorkout()]),
        progress: (_) => Stream.value(started),
        load: () async =>
            const AthleteDashboardPage(events: [], isBounded: false),
      );
      await tester.pumpAndSettle();
      expect(find.text(started ? 'Continue' : 'Begin'), findsOneWidget);
      expect(find.text(started ? 'In progress' : 'Scheduled'), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('workout-start-action-today')));
      await tester.pumpAndSettle();
      expect(find.text('Workout today'), findsOneWidget);
    });
  }

  testWidgets('dashboard updates Continue as saved draft state changes',
      (tester) async {
    final progress = StreamController<bool>();
    addTearDown(progress.close);
    progress.add(false);
    await _pumpDashboard(
      tester,
      progress: (_) => progress.stream,
      schedule: (_) => Stream.value([_todayWorkout()]),
      load: () async =>
          const AthleteDashboardPage(events: [], isBounded: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Begin'), findsOneWidget);
    progress.add(true);
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    progress.add(false);
    await tester.pumpAndSettle();
    expect(find.text('Begin'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('loading saved progress uses Open rather than guessing Begin',
      (tester) async {
    final progress = Completer<bool>();
    await _pumpDashboard(
      tester,
      progress: (_) => Stream.fromFuture(progress.future),
      schedule: (_) => Stream.value([_todayWorkout()]),
      load: () async =>
          const AthleteDashboardPage(events: [], isBounded: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Begin'), findsNothing);
    progress.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('failed saved-progress lookup is explicit and retryable',
      (tester) async {
    var attempts = 0;
    await _pumpDashboard(
      tester,
      progress: (_) => ++attempts == 1
          ? Stream.error(StateError('progress unavailable'))
          : Stream.value(true),
      schedule: (_) => Stream.value([_todayWorkout()]),
      load: () async =>
          const AthleteDashboardPage(events: [], isBounded: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Begin'), findsNothing);
    await tester.tap(find.byTooltip('Unable to load saved progress. Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('progress unavailable'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('completed workouts do not load drafts or show start actions',
      (tester) async {
    await _pumpDashboard(
      tester,
      progress: (_) =>
          throw StateError('Completed workouts must not read drafts'),
      schedule: (_) => Stream.value([
        _todayWorkout(status: WorkoutInstanceStatus.completed),
      ]),
      load: () async =>
          const AthleteDashboardPage(events: [], isBounded: false),
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('workout-start-action-today')), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

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
      expect(find.byType(CircularProgressIndicator), findsWidgets);

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

  testWidgets('All includes today and groups every activity category once',
      (tester) async {
    DateRange? requestedRange;
    await _pumpDashboard(
      tester,
      schedule: (range) {
        requestedRange = range;
        return Stream.value([_todayWorkout()]);
      },
      load: () async => AthleteDashboardPage(
        events: [
          AthleteCommentActivityEvent(
            id: 'comment:new',
            occurredAt: DateTime(2026, 11, 7, 12),
            workoutInstanceId: 'completed',
            comment: 'Newest comment',
            authorName: 'Coach',
          ),
          AthleteCompletionActivityEvent(
            id: 'completion:1',
            occurredAt: DateTime(2026, 11, 7, 11),
            workoutInstanceId: 'completed',
            workoutName: 'Pull session',
            rpe: 7,
            durationMinutes: 40,
          ),
          AthleteReactionActivityEvent(
            id: 'reaction:1',
            occurredAt: DateTime(2026, 11, 7, 10),
            workoutInstanceId: 'completed',
            reactionId: 'celebrate',
            actorName: 'Coach',
          ),
          AthleteCommentActivityEvent(
            id: 'comment:old',
            occurredAt: DateTime(2026, 11, 7, 9),
            workoutInstanceId: 'completed',
            comment: 'Older comment',
            authorName: 'You',
          ),
        ],
        isBounded: false,
      ),
    );
    await tester.pumpAndSettle();
    final today = _todayWorkout().scheduledDate;
    expect(requestedRange!.startDate, today);
    expect(requestedRange!.endDate, today);
    expect(find.text('Begin'), findsOneWidget);
    expect(find.text('You completed Pull session'), findsOneWidget);
    expect(find.text('Coach reacted'), findsOneWidget);
    var previousY = -1.0;
    for (final category in [
      'todaysWorkouts',
      'completion',
      'comment',
      'reaction'
    ]) {
      final heading = find.byKey(Key('athlete-dashboard-section-$category'));
      expect(heading, findsOneWidget);
      final y = tester.getTopLeft(heading).dy;
      expect(y, greaterThan(previousY));
      previousY = y;
    }
    expect(tester.getTopLeft(find.textContaining('Newest comment')).dy,
        lessThan(tester.getTopLeft(find.textContaining('Older comment')).dy));

    await tester.ensureVisible(
        find.byKey(const Key('athlete-dashboard-filter-todaysWorkouts')));
    await tester
        .tap(find.byKey(const Key('athlete-dashboard-filter-todaysWorkouts')));
    await tester.pumpAndSettle();
    expect(find.text('Begin'), findsOneWidget);
    expect(find.text('You completed Pull session'), findsNothing);
    expect(find.byKey(const Key('athlete-dashboard-section-todaysWorkouts')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today remains visible when recent activity fails',
      (tester) async {
    await _pumpDashboard(
      tester,
      schedule: (_) => Stream.value([_todayWorkout()]),
      load: () => Future.error(StateError('activity failed')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Begin'), findsOneWidget);
    expect(find.text('Unable to load activity'), findsOneWidget);
    expect(find.text('No workouts scheduled today'), findsNothing);
  });

  testWidgets('All surfaces and retries a failed today schedule',
      (tester) async {
    var attempts = 0;
    await _pumpDashboard(
      tester,
      schedule: (_) {
        attempts++;
        return attempts == 1
            ? Stream.error(StateError('schedule failed'))
            : Stream.value([_todayWorkout()]);
      },
      load: () async =>
          const AthleteDashboardPage(events: [], isBounded: false),
    );
    await tester.pumpAndSettle();
    expect(find.text("Unable to load today's workouts"), findsOneWidget);
    expect(find.text('No recent activity'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Begin'), findsOneWidget);
    expect(find.text("Unable to load today's workouts"), findsNothing);
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Future<AthleteDashboardPage> Function() load,
  Stream<List<WorkoutInstance>> Function(DateRange range)? schedule,
  Stream<bool> Function(String instanceId)? progress,
  GoRouter? router,
}) {
  final firestore = FakeFirebaseFirestore();
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        athleteDashboardProvider.overrideWith((ref) => load()),
        athleteScheduleProvider.overrideWith(
            (ref, range) => schedule?.call(range) ?? Stream.value([])),
        workoutHasSavedDraftProvider.overrideWith(
            (ref, id) => progress?.call(id) ?? Stream.value(false)),
        workoutTemplateRepositoryProvider
            .overrideWithValue(WorkoutTemplateRepository(firestore: firestore)),
        programRepositoryProvider
            .overrideWithValue(ProgramRepository(firestore: firestore)),
      ],
      child: router == null
          ? const MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(child: AthleteDashboardView())),
            )
          : MaterialApp.router(routerConfig: router),
    ),
  );
}

WorkoutInstance _todayWorkout({
  WorkoutInstanceStatus status = WorkoutInstanceStatus.scheduled,
}) {
  final now = DateTime.now();
  return WorkoutInstance(
    id: 'today',
    programId: 'program-1',
    athleteId: 'athlete-1',
    workoutTemplateId: 'workout-1',
    workoutTemplateVersion: 1,
    scheduledDate: now.toIso8601String().substring(0, 10),
    assignedBy: 'trainer-1',
    assignedAt: now,
    status: status,
    workoutType: WorkoutType.fullBody,
    createdAt: now,
    updatedAt: now,
  );
}
