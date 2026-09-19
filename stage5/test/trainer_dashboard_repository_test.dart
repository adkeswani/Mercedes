import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/trainer_dashboard/data/trainer_dashboard_repository.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late TrainerDashboardRepository repository;
  final now = DateTime(2026, 9, 19, 12);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = TrainerDashboardRepository(
      firestore: firestore,
      now: () => now,
    );
    await _relationship(firestore, 'trainer-1', 'athlete-1', 'active');
    await _relationship(firestore, 'trainer-1', 'athlete-ended', 'ended');
    await _relationship(firestore, 'trainer-2', 'athlete-other', 'active');
    await firestore.collection('users').doc('athlete-1').set({
      'displayName': 'Ada Athlete',
    });
    await firestore.collection('programs').doc('program-1').set({
      'ownerId': 'trainer-1',
      'name': 'Strength Foundations',
    });
    await firestore.collection('programs').doc('other-program').set({
      'ownerId': 'trainer-2',
      'name': 'Other Program',
    });
    await firestore.collection('workoutTemplates').doc('workout-1').set({
      'name': 'Heavy Pull',
    });
  });

  group('activity domain', () {
    test('centralizes ending boundary and filter behavior', () {
      expect(trainerProgramEndingSoonDays, 7);
      expect(
        calendarDaysRemaining(
          DateTime(2026, 9, 19, 23, 59),
          DateTime(2026, 9, 26),
        ),
        7,
      );
      final completion = _completionEvent();
      final comment = CommentActivityEvent(
        id: 'comment:1',
        occurredAt: now,
        athleteId: 'athlete-1',
        athleteName: 'Ada Athlete',
        workoutInstanceId: 'completed-1',
        comment: 'Nice work',
        authorName: 'Coach',
      );
      expect(
        filterTrainerActivityEvents([
          completion,
          comment,
        ], TrainerActivityFilter.completions),
        [completion],
      );
      expect(
        filterTrainerActivityEvents([
          completion,
          comment,
        ], TrainerActivityFilter.personalBests),
        isEmpty,
      );
      expect(
        coachingReactions.map((reaction) => reaction.id).toSet().length,
        coachingReactions.length,
      );
      expect(
        trainerDashboardCanaryContentFor([
          CompletionActivityEvent(
            id: 'completion:canary',
            occurredAt: DateTime(2026, 9, 19, 12),
            athleteId: 'athlete-1',
            athleteName: 'Ada Athlete',
            workoutInstanceId: 'canary',
            workoutName: 'Release Canary Workout',
            programId: 'program-1',
            rpe: 8,
            durationMinutes: 42,
            latestComment: 'Release Canary dashboard comment',
            reactionCounts: const {'celebrate': 1},
          ),
          CommentActivityEvent(
            id: 'comment:canary',
            occurredAt: DateTime(2026, 9, 19, 12, 1),
            athleteId: 'athlete-1',
            athleteName: 'Ada Athlete',
            workoutInstanceId: 'canary',
            comment: 'Release Canary dashboard comment',
            authorName: 'Coach',
          ),
          ReactionActivityEvent(
            id: 'reaction:canary',
            occurredAt: DateTime(2026, 9, 19, 12, 2),
            athleteId: 'athlete-1',
            athleteName: 'Ada Athlete',
            workoutInstanceId: 'canary',
            reactionId: 'celebrate',
            actorName: 'Coach',
          ),
          ProgramEndingSoonActivityEvent(
            id: 'program-ending:canary',
            occurredAt: DateTime(2026, 9, 26, 23, 59),
            athleteId: 'athlete-1',
            athleteName: 'Ada Athlete',
            programInstanceId: 'program-instance-canary',
            programId: 'program-1',
            programName: 'Release Canary Program',
            endDate: '2026-09-26',
            daysRemaining: 7,
          ),
        ]),
        'Program ending soon: Release Canary Program (7 days) | '
        'Reaction: 🎉 1 | Comment: Release Canary dashboard comment | '
        'Completion: Release Canary Workout',
      );
    });

    test('targets the latest comment when discussion exists', () async {
      await _workout(
        firestore,
        id: 'completed-1',
        completedAt: DateTime(2026, 9, 19, 10),
      );
      final messageId = await repository.addQuickComment(
        trainerId: 'trainer-1',
        workoutInstanceId: 'completed-1',
        body: 'Strong session',
      );

      await repository.toggleReaction(
        trainerId: 'trainer-1',
        workoutInstanceId: 'completed-1',
        reactionId: 'celebrate',
      );

      final reaction = await firestore
          .collection('workoutDiscussionThreads')
          .doc('completed-1')
          .collection('threadMessages')
          .doc(messageId)
          .collection('reactions')
          .doc('trainer-1')
          .get();
      expect(reaction.data()?['reactionId'], 'celebrate');
      expect(
        (await firestore
                .collection('workoutDiscussionThreads')
                .doc('completed-1')
                .collection('threadMessages')
                .doc('completion-activity')
                .get())
            .exists,
        isFalse,
      );
    });
  });

  group('loadInitialPage', () {
    test('orders and scopes the unified bounded activity feed', () async {
      await _workout(
        firestore,
        id: 'completed-1',
        completedAt: DateTime(2026, 9, 19, 10),
      );
      await _workout(
        firestore,
        id: 'ended-client-completion',
        athleteId: 'athlete-ended',
        completedAt: DateTime(2026, 9, 19, 11),
      );
      await _workout(
        firestore,
        id: 'other-trainer-completion',
        trainerId: 'trainer-2',
        athleteId: 'athlete-other',
        programId: 'other-program',
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
        'createdAt': DateTime(2026, 9, 19, 8),
        'createdBy': 'athlete-1',
      });
      await thread.collection('threadMessages').doc('new').set({
        'authorId': 'trainer-1',
        'body': 'Latest coaching note',
        'createdAt': DateTime(2026, 9, 19, 9),
      });
      await thread
          .collection('threadMessages')
          .doc('new')
          .collection('reactions')
          .doc('trainer-1')
          .set({
        'actorId': 'trainer-1',
        'reactionId': 'strong',
        'createdAt': DateTime(2026, 9, 19, 8),
      });
      await thread
          .collection('threadMessages')
          .doc('new')
          .collection('reactions')
          .doc('athlete-1')
          .set({
        'actorId': 'athlete-1',
        'reactionId': 'strong',
        'createdAt': DateTime(2026, 9, 19, 8),
      });
      await _programInstance(
        firestore,
        id: 'ends-today',
        endDate: '2026-09-19',
      );
      await _programInstance(
        firestore,
        id: 'ends-day-7',
        endDate: '2026-09-26',
      );
      await _programInstance(
        firestore,
        id: 'ends-day-8',
        endDate: '2026-09-27',
      );
      await _programInstance(firestore, id: 'past', endDate: '2026-09-18');
      await _programInstance(
        firestore,
        id: 'cancelled',
        endDate: '2026-09-20',
        status: 'cancelled',
      );
      await _programInstance(
        firestore,
        id: 'unlinked',
        endDate: '2026-09-20',
        relationshipMode: 'copied',
        unlinkedAt: now,
      );

      final page = await repository.loadInitialPage('trainer-1');

      expect(page.events, hasLength(6));
      expect(page.events.map((event) => event.id), [
        'program-ending:ends-day-7',
        'program-ending:ends-today',
        'completion:completed-1',
        'comment:completed-1:new',
        'reaction:completed-1:new:athlete-1',
        'reaction:completed-1:new:trainer-1',
      ]);
      final completion =
          page.events.whereType<CompletionActivityEvent>().single;
      expect(completion.athleteName, 'Ada Athlete');
      expect(completion.workoutName, 'Heavy Pull');
      expect(completion.latestComment, 'Latest coaching note');
      expect(completion.reactionCounts, {'strong': 2});
      expect(completion.currentTrainerReaction, 'strong');

      final ending =
          page.events.whereType<ProgramEndingSoonActivityEvent>().toList();
      expect(ending.map((event) => event.daysRemaining), [7, 0]);
      expect(ending.first.programName, 'Strength Foundations');
      expect(ending.first.endDate, '2026-09-26');
    });

    test('excludes program with a mismatched current owner', () async {
      await _programInstance(
        firestore,
        id: 'wrong-owner',
        endDate: '2026-09-20',
        sourceProgramId: 'other-program',
      );

      final page = await repository.loadInitialPage('trainer-1');

      expect(page.events, isEmpty);
    });

    test('requires a non-empty authenticated trainer identity', () {
      expect(() => repository.loadInitialPage(''), throwsStateError);
    });

    test('new activity on the 51st-oldest completion remains visible',
        () async {
      for (var index = 0; index < 51; index++) {
        final completedAt = now.subtract(Duration(minutes: index));
        final thread = firestore
            .collection('workoutDiscussionThreads')
            .doc('activity-$index');
        await thread.set({
          'workoutInstanceId': 'activity-$index',
          'athleteId': 'athlete-1',
          'trainerId': 'trainer-1',
          'completedAt': completedAt,
          'lastActivityAt':
              index == 50 ? now.add(const Duration(minutes: 1)) : completedAt,
          'createdAt': completedAt,
          'createdBy': 'athlete-1',
        });
        if (index == 50) {
          await thread.collection('threadMessages').doc('newest-comment').set({
            'authorId': 'athlete-1',
            'body': 'Newest interaction on oldest completion',
            'createdAt': now.add(const Duration(minutes: 1)),
          });
        }
      }

      final page = await repository.loadInitialPage('trainer-1');

      expect(
        page.events
            .whereType<CommentActivityEvent>()
            .map((event) => event.comment),
        contains('Newest interaction on oldest completion'),
      );
    });

    test('caps the initial completion query and marks the page bounded',
        () async {
      for (var index = 0;
          index < trainerDashboardCompletionQueryLimit + 1;
          index++) {
        await _workout(
          firestore,
          id: 'completion-$index',
          completedAt: now.subtract(Duration(minutes: index)),
        );
      }

      final page = await repository.loadInitialPage('trainer-1');

      expect(page.events, hasLength(trainerDashboardCompletionQueryLimit));
      expect(page.isBounded, isTrue);
      expect(page.events.first.id, 'completion:completion-0');
      expect(
        page.events.any(
          (event) =>
              event.id ==
              'completion:completion-$trainerDashboardCompletionQueryLimit',
        ),
        isFalse,
      );
    });
  });

  group('coaching mutations', () {
    setUp(() async {
      await _workout(
        firestore,
        id: 'completed-1',
        completedAt: DateTime(2026, 9, 19, 10),
      );
    });

    test('writes append-only comment without mutating workout history',
        () async {
      final before = (await firestore
              .collection('workoutInstances')
              .doc('completed-1')
              .get())
          .data();

      final messageId = await repository.addQuickComment(
        trainerId: 'trainer-1',
        workoutInstanceId: 'completed-1',
        body: '  Excellent control  ',
      );

      final message = await firestore
          .collection('workoutDiscussionThreads')
          .doc('completed-1')
          .collection('threadMessages')
          .doc(messageId)
          .get();
      expect(message.data()?['body'], 'Excellent control');
      expect(message.data()?['authorId'], 'trainer-1');
      expect(
        message.data()?.keys.toSet(),
        {'authorId', 'body', 'createdAt'},
      );
      final thread = await firestore
          .collection('workoutDiscussionThreads')
          .doc('completed-1')
          .get();
      expect(
        thread.data()?.keys.toSet(),
        {
          'workoutInstanceId',
          'athleteId',
          'trainerId',
          'completedAt',
          'lastActivityAt',
          'createdAt',
          'createdBy',
        },
      );
      expect(thread.data()?['lastActivityAt'], isNotNull);
      final after = (await firestore
              .collection('workoutInstances')
              .doc('completed-1')
              .get())
          .data();
      expect(after, before);
    });

    test(
      'reaction selection, replacement, and removal are idempotent',
      () async {
        expect(
          await repository.toggleReaction(
            trainerId: 'trainer-1',
            workoutInstanceId: 'completed-1',
            reactionId: 'strong',
          ),
          isTrue,
        );
        var reaction = await _reaction(firestore);
        expect(reaction?['reactionId'], 'strong');
        expect(
          reaction?.keys.toSet(),
          {'actorId', 'reactionId', 'createdAt'},
        );

        expect(
          await repository.toggleReaction(
            trainerId: 'trainer-1',
            workoutInstanceId: 'completed-1',
            reactionId: 'celebrate',
          ),
          isTrue,
        );
        reaction = await _reaction(firestore);
        expect(reaction?['reactionId'], 'celebrate');
        final activityBeforeRemoval = (await firestore
                .collection('workoutDiscussionThreads')
                .doc('completed-1')
                .get())
            .data()?['lastActivityAt'];

        expect(
          await repository.toggleReaction(
            trainerId: 'trainer-1',
            workoutInstanceId: 'completed-1',
            reactionId: 'celebrate',
          ),
          isFalse,
        );
        expect(await _reaction(firestore), isNull);
        final activityAfterRemoval = (await firestore
                .collection('workoutDiscussionThreads')
                .doc('completed-1')
                .get())
            .data()?['lastActivityAt'];
        expect(activityAfterRemoval, activityBeforeRemoval);
      },
    );

    test('rejects invalid reaction and blank comment', () {
      expect(
        () => repository.toggleReaction(
          trainerId: 'trainer-1',
          workoutInstanceId: 'completed-1',
          reactionId: 'fire',
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.addQuickComment(
          trainerId: 'trainer-1',
          workoutInstanceId: 'completed-1',
          body: ' ',
        ),
        throwsArgumentError,
      );
    });

    test(
      'enforces workout owner, program owner, relationship, and status',
      () async {
        await _workout(
          firestore,
          id: 'scheduled',
          status: 'scheduled',
          completedAt: null,
        );
        await _workout(
          firestore,
          id: 'wrong-workout-owner',
          trainerId: 'trainer-2',
          programId: 'other-program',
          completedAt: now,
        );
        await _workout(
          firestore,
          id: 'ended-workout',
          athleteId: 'athlete-ended',
          completedAt: now,
        );
        await firestore.collection('programs').doc('program-1').update({
          'ownerId': 'trainer-2',
        });
        await expectLater(
          repository.addQuickComment(
            trainerId: 'trainer-1',
            workoutInstanceId: 'completed-1',
            body: 'No',
          ),
          throwsStateError,
        );
        await firestore.collection('programs').doc('program-1').update({
          'ownerId': 'trainer-1',
        });
        for (final id in [
          'scheduled',
          'wrong-workout-owner',
          'ended-workout',
        ]) {
          await expectLater(
            repository.addQuickComment(
              trainerId: 'trainer-1',
              workoutInstanceId: id,
              body: 'No',
            ),
            throwsStateError,
          );
        }
      },
    );
  });
}

Future<void> _relationship(
  FakeFirebaseFirestore firestore,
  String trainerId,
  String athleteId,
  String status,
) {
  return firestore
      .collection('trainerClientRelationships')
      .doc('${trainerId}_$athleteId')
      .set({'trainerId': trainerId, 'athleteId': athleteId, 'status': status});
}

Future<void> _workout(
  FakeFirebaseFirestore firestore, {
  required String id,
  DateTime? completedAt,
  String trainerId = 'trainer-1',
  String athleteId = 'athlete-1',
  String programId = 'program-1',
  String status = 'completed',
}) {
  return firestore.collection('workoutInstances').doc(id).set({
    'programOwnerId': trainerId,
    'athleteId': athleteId,
    'programId': programId,
    'workoutTemplateId': 'workout-1',
    'status': status,
    'completedAt': completedAt,
    'rpe': 8,
    'durationMinutes': 42,
  });
}

Future<void> _programInstance(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String endDate,
  String status = 'active',
  String relationshipMode = 'subscribed',
  String sourceProgramId = 'program-1',
  DateTime? unlinkedAt,
}) {
  return firestore.collection('athleteProgramInstances').doc(id).set({
    'assigningTrainerId': 'trainer-1',
    'athleteOwnerId': 'athlete-1',
    'sourceProgramId': sourceProgramId,
    'status': status,
    'relationshipMode': relationshipMode,
    'expectedEndDate': endDate,
    'unlinkedAt': unlinkedAt,
  });
}

Future<Map<String, dynamic>?> _reaction(FakeFirebaseFirestore firestore) async {
  final snapshot = await firestore
      .collection('workoutDiscussionThreads')
      .doc('completed-1')
      .collection('threadMessages')
      .doc('completion-activity')
      .collection('reactions')
      .doc('trainer-1')
      .get();
  return snapshot.data();
}

CompletionActivityEvent _completionEvent() {
  return CompletionActivityEvent(
    id: 'completion:completed-1',
    occurredAt: DateTime(2026, 9, 19, 10),
    athleteId: 'athlete-1',
    athleteName: 'Ada Athlete',
    workoutInstanceId: 'completed-1',
    workoutName: 'Heavy Pull',
    programId: 'program-1',
    rpe: 8,
    durationMinutes: 42,
    reactionCounts: const {},
  );
}
