import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';
import 'package:stage5/features/trainer_dashboard/presentation/trainer_dashboard_providers.dart';
import 'package:stage5/features/trainer_dashboard/presentation/trainer_dashboard_screen.dart';

void main() {
  testWidgets('shows loading then filter-specific empty states', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final completer = Completer<TrainerDashboardPage>();
    await _pumpDashboard(tester, load: () => completer.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Loading trainer activity')),
      findsOneWidget,
    );

    completer.complete(
      const TrainerDashboardPage(events: [], isBounded: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('No recent client activity'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('trainer-dashboard-filter-comments')),
    );
    await tester.pump();
    expect(find.text('No recent comments'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('trainer-dashboard-filter-programs')),
    );
    await tester.pump();
    expect(find.text('No programs ending soon'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shows an error with a working retry action', (tester) async {
    var attempts = 0;
    await _pumpDashboard(
      tester,
      load: () {
        attempts++;
        if (attempts == 1) {
          return Future.error(StateError('permission-denied'));
        }
        return Future.value(
          const TrainerDashboardPage(events: [], isBounded: false),
        );
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load trainer activity'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('No recent client activity'), findsOneWidget);
  });

  testWidgets('renders completion and program details responsively', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await _pumpDashboard(
      tester,
      load: () async => TrainerDashboardPage(
        events: [
          _completion(),
          ProgramEndingSoonActivityEvent(
            id: 'program-ending:instance-1',
            occurredAt: DateTime(2026, 9, 26),
            athleteId: 'athlete-1',
            athleteName: 'Ada Athlete',
            programInstanceId: 'instance-1',
            programId: 'program-1',
            programName: 'Strength Foundations',
            endDate: '2026-09-26',
            daysRemaining: 7,
          ),
        ],
        isBounded: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ada Athlete'), findsWidgets);
    expect(find.text('Heavy Pull completed'), findsOneWidget);
    expect(find.text('RPE 8'), findsOneWidget);
    expect(find.text('42 min'), findsOneWidget);
    expect(find.text('Latest coaching note'), findsOneWidget);
    expect(find.text('Strength Foundations ends soon'), findsOneWidget);
    expect(find.textContaining('September 26, 2026'), findsOneWidget);
    expect(find.textContaining('7 days remaining'), findsOneWidget);
    expect(find.text('View program'), findsOneWidget);
    expect(find.text('Showing the newest activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps completion controls usable on a narrow mobile surface', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await _pumpDashboard(
      tester,
      load: () async =>
          TrainerDashboardPage(events: [_completion()], isBounded: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Heavy Pull completed'), findsOneWidget);
    expect(
      find.byKey(const Key('quick-comment-completed-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters event types and exposes disabled PB placeholder', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpDashboard(
      tester,
      load: () async => TrainerDashboardPage(
        events: [
          _completion(),
          CommentActivityEvent(
            id: 'comment:1',
            occurredAt: DateTime(2026, 9, 19, 9),
            athleteId: 'athlete-1',
            athleteName: 'Ada Athlete',
            workoutInstanceId: 'completed-1',
            comment: 'Keep your brace tight',
            authorName: 'Coach',
          ),
          ReactionActivityEvent(
            id: 'reaction:1',
            occurredAt: DateTime(2026, 9, 19, 8),
            athleteId: 'athlete-1',
            athleteName: 'Ada Athlete',
            workoutInstanceId: 'completed-1',
            reactionId: 'celebrate',
            actorName: 'Coach',
          ),
        ],
        isBounded: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Activity filters'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Personal bests — Coming later filter'),
      findsOneWidget,
    );
    final pbChip = tester.widget<FilterChip>(
      find.byKey(const Key('trainer-dashboard-filter-personalBests')),
    );
    expect(pbChip.onSelected, isNull);

    await tester.tap(
      find.byKey(const Key('trainer-dashboard-filter-comments')),
    );
    await tester.pump();
    expect(find.textContaining('Keep your brace tight'), findsOneWidget);
    expect(find.text('Heavy Pull completed'), findsNothing);
    expect(find.textContaining('🎉 Celebrate'), findsNothing);

    await tester.tap(
      find.byKey(const Key('trainer-dashboard-filter-reactions')),
    );
    await tester.pump();
    expect(find.textContaining('🎉 Celebrate'), findsOneWidget);
    expect(find.textContaining('Keep your brace tight'), findsNothing);
    semantics.dispose();
  });

  testWidgets('shows posting states and clears a successful comment', (
    tester,
  ) async {
    final commentCompleter = Completer<void>();
    final reactionCompleter = Completer<void>();
    await _pumpDashboard(
      tester,
      load: () async =>
          TrainerDashboardPage(events: [_completion()], isBounded: false),
      onQuickComment: (_, __) => commentCompleter.future,
      onReaction: (_, __) => reactionCompleter.future,
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('quick-comment-completed-1'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Great tempo');
    await tester.tap(find.byKey(const Key('post-comment-completed-1')));
    await tester.pump();
    expect(find.text('Posting…'), findsOneWidget);

    commentCompleter.complete();
    await tester.pumpAndSettle();
    expect(find.text('Posting…'), findsNothing);
    expect(tester.widget<TextField>(field).controller?.text, isEmpty);

    final reaction = find.byKey(const Key('reaction-completed-1-celebrate'));
    await tester.ensureVisible(reaction);
    await tester.tap(reaction);
    await tester.pump();
    expect(
      find.descendant(
        of: reaction,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    reactionCompleter.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('surfaces mutation failure without removing history', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      load: () async =>
          TrainerDashboardPage(events: [_completion()], isBounded: false),
      onQuickComment: (_, __) => Future.error(StateError('relationship ended')),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('quick-comment-completed-1'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Should fail');
    await tester.tap(find.byKey(const Key('post-comment-completed-1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not post comment'), findsOneWidget);
    expect(find.text('Heavy Pull completed'), findsOneWidget);
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Future<TrainerDashboardPage> Function() load,
  QuickCommentCallback? onQuickComment,
  ReactionCallback? onReaction,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [trainerDashboardProvider.overrideWith((ref) => load())],
      child: MaterialApp(
        home: Scaffold(
          body: TrainerDashboardScreen(
            onQuickComment: onQuickComment,
            onReaction: onReaction,
          ),
        ),
      ),
    ),
  );
}

CompletionActivityEvent _completion() {
  return CompletionActivityEvent(
    id: 'completion:completed-1',
    occurredAt: DateTime(2026, 9, 19, 10, 15),
    athleteId: 'athlete-1',
    athleteName: 'Ada Athlete',
    workoutInstanceId: 'completed-1',
    workoutName: 'Heavy Pull',
    programId: 'program-1',
    rpe: 8,
    durationMinutes: 42,
    latestComment: 'Latest coaching note',
    reactionCounts: const {'strong': 2},
    currentTrainerReaction: 'strong',
  );
}
