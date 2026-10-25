import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/athlete_dashboard/data/athlete_dashboard_repository.dart';
import 'package:stage5/features/athlete_dashboard/domain/athlete_activity_event.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AthleteDashboardRepository repository;
  final now = DateTime(2026, 9, 19, 12);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = AthleteDashboardRepository(
      firestore: firestore,
      now: () => now,
    );
    await firestore.collection('workoutTemplates').doc('workout-1').set({
      'name': 'Heavy Pull',
    });
  });

  group('activity domain', () {
    test('filters events by type, leaving completions out of the feed', () {
      final completion = AthleteCompletionActivityEvent(
        id: 'completion:1',
        occurredAt: DateTime(2026, 9, 19),
        workoutInstanceId: 'completed-1',
        workoutName: 'Heavy Pull',
        rpe: 8,
        durationMinutes: 42,
      );
      final comment = AthleteCommentActivityEvent(
        id: 'comment:1',
        occurredAt: DateTime(2026, 9, 19),
        workoutInstanceId: 'completed-1',
        comment: 'Nice work',
        authorName: 'Coach',
      );
      final reaction = AthleteReactionActivityEvent(
        id: 'reaction:1',
        occurredAt: DateTime(2026, 9, 19),
        workoutInstanceId: 'completed-1',
        reactionId: 'celebrate',
        actorName: 'You',
      );

      expect(
        filterAthleteActivityEvents(
          [completion, comment, reaction],
          AthleteActivityFilter.all,
        ),
        [completion, comment, reaction],
      );
      expect(
        filterAthleteActivityEvents(
          [completion, comment, reaction],
          AthleteActivityFilter.comments,
        ),
        [comment],
      );
      expect(
        filterAthleteActivityEvents(
          [completion, comment, reaction],
          AthleteActivityFilter.completed,
        ),
        [completion],
      );
      expect(
        filterAthleteActivityEvents(
          [completion, comment, reaction],
          AthleteActivityFilter.reactions,
        ),
        [reaction],
      );
      // Today's Workouts is backed by a separate schedule view, not events.
      expect(
        filterAthleteActivityEvents(
          [completion, comment, reaction],
          AthleteActivityFilter.todaysWorkouts,
        ),
        [completion, comment, reaction],
      );
    });
  });

  group('loadInitialPage', () {
    test('orders completions, comments, and reactions for one athlete',
        () async {
      await _workout(
        firestore,
        id: 'completed-1',
        completedAt: DateTime(2026, 9, 19, 10),
      );
      await _workout(
        firestore,
        id: 'other-athlete-completion',
        athleteId: 'athlete-other',
        completedAt: DateTime(2026, 9, 19, 11),
      );
      await _workout(
        firestore,
        id: 'not-completed',
        status: 'scheduled',
        completedAt: null,
      );

      final thread =
          firestore.collection('workoutDiscussionThreads').doc('completed-1');
      await thread.set({
        'workoutInstanceId': 'completed-1',
        'athleteId': 'athlete-1',
        'trainerId': 'trainer-1',
        'completedAt': DateTime(2026, 9, 19, 10),
        'lastActivityAt': DateTime(2026, 9, 19, 9),
        'createdAt': DateTime(2026, 9, 19, 8),
        'createdBy': 'athlete-1',
      });
      await thread.collection('threadMessages').doc('new').set({
        'authorId': 'trainer-1',
        'body': 'Great session',
        'createdAt': DateTime(2026, 9, 19, 9),
      });
      await thread
          .collection('threadMessages')
          .doc('new')
          .collection('reactions')
          .doc('athlete-1')
          .set({
        'actorId': 'athlete-1',
        'reactionId': 'celebrate',
        'createdAt': DateTime(2026, 9, 19, 9, 30),
      });

      final page = await repository.loadInitialPage('athlete-1');

      expect(page.events.map((event) => event.id), [
        'completion:completed-1',
        'reaction:completed-1:new:athlete-1',
        'comment:completed-1:new',
      ]);
      final completion =
          page.events.whereType<AthleteCompletionActivityEvent>().single;
      expect(completion.workoutName, 'Heavy Pull');
      expect(completion.rpe, 8);
      expect(completion.durationMinutes, 42);

      final comment =
          page.events.whereType<AthleteCommentActivityEvent>().single;
      expect(comment.comment, 'Great session');
      expect(comment.authorName, 'Coach');

      final reaction =
          page.events.whereType<AthleteReactionActivityEvent>().single;
      expect(reaction.reactionId, 'celebrate');
      expect(reaction.actorName, 'You');
      expect(page.isBounded, isFalse);
    });

    test('requires a non-empty authenticated athlete identity', () {
      expect(() => repository.loadInitialPage(''), throwsStateError);
    });

    test('returns an empty page when there is no activity', () async {
      final page = await repository.loadInitialPage('athlete-1');
      expect(page.events, isEmpty);
      expect(page.isBounded, isFalse);
    });

    test('excludes completions and discussion activity older than the '
        'query window', () async {
      // Within the 7-day window relative to `now`.
      await _workout(
        firestore,
        id: 'recent',
        completedAt: now.subtract(const Duration(days: 2)),
      );
      // Outside the 7-day window.
      await _workout(
        firestore,
        id: 'stale',
        completedAt: now.subtract(const Duration(days: 10)),
      );

      final recentThread =
          firestore.collection('workoutDiscussionThreads').doc('recent');
      await recentThread.set({
        'workoutInstanceId': 'recent',
        'athleteId': 'athlete-1',
        'trainerId': 'trainer-1',
        'completedAt': now.subtract(const Duration(days: 2)),
        'lastActivityAt': now.subtract(const Duration(days: 1)),
        'createdAt': now.subtract(const Duration(days: 2)),
        'createdBy': 'athlete-1',
      });
      await recentThread.collection('threadMessages').doc('new').set({
        'authorId': 'trainer-1',
        'body': 'Nice work this week',
        'createdAt': now.subtract(const Duration(days: 1)),
      });

      final staleThread =
          firestore.collection('workoutDiscussionThreads').doc('stale');
      await staleThread.set({
        'workoutInstanceId': 'stale',
        'athleteId': 'athlete-1',
        'trainerId': 'trainer-1',
        'completedAt': now.subtract(const Duration(days: 10)),
        'lastActivityAt': now.subtract(const Duration(days: 10)),
        'createdAt': now.subtract(const Duration(days: 10)),
        'createdBy': 'athlete-1',
      });
      await staleThread.collection('threadMessages').doc('old').set({
        'authorId': 'trainer-1',
        'body': 'From over a week ago',
        'createdAt': now.subtract(const Duration(days: 10)),
      });

      final page = await repository.loadInitialPage('athlete-1');

      expect(page.events.map((event) => event.id), [
        'comment:recent:new',
        'completion:recent',
      ]);
    });
  });
}

Future<void> _workout(
  FakeFirebaseFirestore firestore, {
  required String id,
  DateTime? completedAt,
  String athleteId = 'athlete-1',
  String status = 'completed',
}) {
  return firestore.collection('workoutInstances').doc(id).set({
    'programOwnerId': 'trainer-1',
    'athleteId': athleteId,
    'programId': 'program-1',
    'workoutTemplateId': 'workout-1',
    'status': status,
    'completedAt': completedAt,
    'rpe': 8,
    'durationMinutes': 42,
  });
}
