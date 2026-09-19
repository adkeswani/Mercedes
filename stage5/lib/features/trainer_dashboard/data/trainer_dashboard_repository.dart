import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';

class TrainerDashboardRepository {
  TrainerDashboardRepository({
    FirebaseFirestore? firestore,
    DateTime Function()? now,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _now = now ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;
  static const _completionActivityMessageId = 'completion-activity';

  Future<TrainerDashboardPage> loadInitialPage(String trainerId) async {
    _verifyAuthenticatedTrainer(trainerId);
    final relationshipSnapshot = await _firestore
        .collection('trainerClientRelationships')
        .where('trainerId', isEqualTo: trainerId)
        .where('status', isEqualTo: 'active')
        .limit(trainerDashboardRelationshipQueryLimit)
        .get();
    final athleteIds = relationshipSnapshot.docs
        .where((doc) => doc.data()['trainerId'] == trainerId)
        .map((doc) => doc.data()['athleteId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (athleteIds.isEmpty) {
      return TrainerDashboardPage(
        events: const [],
        isBounded: relationshipSnapshot.docs.length >=
            trainerDashboardRelationshipQueryLimit,
      );
    }

    final today = _dateOnly(_now());
    final endingBoundary = today.add(
      const Duration(days: trainerProgramEndingSoonDays),
    );
    final profileNames = await _loadNames(athleteIds);
    final completionsFuture = _loadCompletions(trainerId, athleteIds);
    final discussionsFuture = _loadDiscussionActivities(
      trainerId,
      athleteIds,
      profileNames,
    );
    final endingProgramsFuture = _loadEndingPrograms(
      trainerId,
      athleteIds,
      today,
      endingBoundary,
    );
    final completions = await completionsFuture;
    final discussions = await discussionsFuture;
    final endingPrograms = await endingProgramsFuture;
    final events = <TrainerActivityEvent>[];

    for (final completion in completions.documents) {
      final data = completion.data();
      final athleteId = data['athleteId'] as String? ?? '';
      if (!athleteIds.contains(athleteId) ||
          data['programOwnerId'] != trainerId ||
          data['status'] != 'completed') {
        continue;
      }
      final completedAt = _optionalDateTime(data['completedAt']);
      if (completedAt == null) {
        continue;
      }
      final workoutTemplateId = data['workoutTemplateId'] as String? ?? '';
      final workoutName = await _loadDocumentName(
        'workoutTemplates',
        workoutTemplateId,
        'Workout details unavailable',
      );
      final discussion = discussions.summaries[completion.id] ??
          const _DiscussionSummary(
            latestComment: null,
            reactionCounts: {},
            currentTrainerReaction: null,
          );
      events.add(
        CompletionActivityEvent(
          id: 'completion:${completion.id}',
          occurredAt: completedAt,
          athleteId: athleteId,
          athleteName: profileNames[athleteId] ?? 'Athlete',
          workoutInstanceId: completion.id,
          workoutName: workoutName,
          programId: data['programId'] as String? ?? '',
          rpe: (data['rpe'] as num?)?.toInt() ?? 0,
          durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 0,
          latestComment: discussion.latestComment,
          reactionCounts: discussion.reactionCounts,
          currentTrainerReaction: discussion.currentTrainerReaction,
        ),
      );
    }

    events.addAll(discussions.events);

    for (final instance in endingPrograms.documents) {
      final data = instance.data();
      final athleteId = data['athleteOwnerId'] as String? ?? '';
      final endDate = _parseDate(data['expectedEndDate'] as String?);
      if (!athleteIds.contains(athleteId) ||
          data['assigningTrainerId'] != trainerId ||
          data['status'] != 'active' ||
          data['relationshipMode'] != 'subscribed' ||
          data['unlinkedAt'] != null ||
          endDate == null) {
        continue;
      }
      final daysRemaining = calendarDaysRemaining(today, endDate);
      if (daysRemaining < 0 || daysRemaining > trainerProgramEndingSoonDays) {
        continue;
      }
      final programId = data['sourceProgramId'] as String? ?? '';
      final program =
          await _firestore.collection('programs').doc(programId).get();
      if (!program.exists || program.data()?['ownerId'] != trainerId) {
        continue;
      }
      events.add(
        ProgramEndingSoonActivityEvent(
          id: 'program-ending:${instance.id}',
          occurredAt: DateTime(
            endDate.year,
            endDate.month,
            endDate.day,
            23,
            59,
            59,
            999,
          ),
          athleteId: athleteId,
          athleteName: profileNames[athleteId] ?? 'Athlete',
          programInstanceId: instance.id,
          programId: programId,
          programName: program.data()?['name'] as String? ??
              'Program details unavailable',
          endDate: _formatDate(endDate),
          daysRemaining: daysRemaining,
        ),
      );
    }

    events.sort((a, b) {
      final dateOrder = b.occurredAt.compareTo(a.occurredAt);
      return dateOrder != 0 ? dateOrder : a.id.compareTo(b.id);
    });
    final isBounded = events.length > trainerDashboardPageSize ||
        completions.hitLimit ||
        discussions.hitLimit ||
        endingPrograms.hitLimit ||
        relationshipSnapshot.docs.length >=
            trainerDashboardRelationshipQueryLimit;
    return TrainerDashboardPage(
      events: List.unmodifiable(events.take(trainerDashboardPageSize)),
      isBounded: isBounded,
    );
  }

  Future<_BoundedDocuments> _loadCompletions(
    String trainerId,
    Set<String> athleteIds,
  ) {
    return _loadPerAthlete(
      athleteIds: athleteIds,
      perAthleteLimit: trainerDashboardCompletionQueryLimit,
      globalLimit: trainerDashboardCompletionQueryLimit,
      query: (athleteId) => _firestore
          .collection('workoutInstances')
          .where('programOwnerId', isEqualTo: trainerId)
          .where('athleteId', isEqualTo: athleteId)
          .where('status', isEqualTo: 'completed')
          .orderBy('completedAt', descending: true),
      timestamp: (document) =>
          _optionalDateTime(document.data()['completedAt']),
    );
  }

  Future<_DiscussionActivityLoad> _loadDiscussionActivities(
    String trainerId,
    Set<String> athleteIds,
    Map<String, String> profileNames,
  ) async {
    final threads = await _loadDiscussionThreads(
      trainerId,
      athleteIds,
    );
    final events = <TrainerActivityEvent>[];
    final summaries = <String, _DiscussionSummary>{};
    var hitLimit = threads.hitLimit;
    for (final thread in threads.documents) {
      final data = thread.data();
      final athleteId = data['athleteId'] as String? ?? '';
      if (!athleteIds.contains(athleteId) ||
          data['trainerId'] != trainerId ||
          data['workoutInstanceId'] != thread.id) {
        continue;
      }
      final athleteName = profileNames[athleteId] ?? 'Athlete';
      final messages = await thread.reference
          .collection('threadMessages')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      if (messages.docs.length >= 100) {
        hitLimit = true;
      }
      final realMessages = messages.docs
          .where((message) => message.id != _completionActivityMessageId)
          .toList();
      final reactionTargetId = realMessages.isEmpty
          ? _completionActivityMessageId
          : realMessages.first.id;
      final counts = <String, int>{};
      String? currentTrainerReaction;
      String? latestComment;
      for (final message in messages.docs) {
        final isCompletionAnchor = message.id == _completionActivityMessageId;
        final body = (message.data()['body'] as String? ?? '').trim();
        final messageAt = _optionalDateTime(message.data()['createdAt']);
        final authorId = message.data()['authorId'] as String? ?? '';
        if (!isCompletionAnchor && body.isNotEmpty && messageAt != null) {
          latestComment ??= body;
          events.add(
            CommentActivityEvent(
              id: 'comment:${thread.id}:${message.id}',
              occurredAt: messageAt,
              athleteId: athleteId,
              athleteName: athleteName,
              workoutInstanceId: thread.id,
              comment: body,
              authorName: authorId == athleteId ? athleteName : 'Coach',
            ),
          );
        }
        final reactions =
            await message.reference.collection('reactions').limit(100).get();
        if (reactions.docs.length >= 100) {
          hitLimit = true;
        }
        for (final reaction in reactions.docs) {
          final reactionId = reaction.data()['reactionId'] as String? ?? '';
          final definition = _reactionForId(reactionId);
          final reactionAt = _optionalDateTime(reaction.data()['createdAt']);
          final actorId = reaction.data()['actorId'] as String? ?? '';
          if (definition == null || reactionAt == null) {
            continue;
          }
          if (message.id == reactionTargetId) {
            counts[definition.id] = (counts[definition.id] ?? 0) + 1;
            if (actorId == trainerId || reaction.id == trainerId) {
              currentTrainerReaction = definition.id;
            }
          }
          events.add(
            ReactionActivityEvent(
              id: 'reaction:${thread.id}:${message.id}:${reaction.id}',
              occurredAt: reactionAt,
              athleteId: athleteId,
              athleteName: athleteName,
              workoutInstanceId: thread.id,
              reactionId: definition.id,
              actorName: actorId == athleteId ? athleteName : 'Coach',
            ),
          );
        }
      }
      summaries[thread.id] = _DiscussionSummary(
        latestComment: latestComment,
        reactionCounts: Map.unmodifiable(counts),
        currentTrainerReaction: currentTrainerReaction,
      );
    }
    events.sort((a, b) {
      final timeOrder = b.occurredAt.compareTo(a.occurredAt);
      return timeOrder != 0 ? timeOrder : a.id.compareTo(b.id);
    });
    return _DiscussionActivityLoad(
      events: List.unmodifiable(
        events.take(trainerDashboardInteractionQueryLimit),
      ),
      summaries: Map.unmodifiable(summaries),
      hitLimit:
          hitLimit || events.length > trainerDashboardInteractionQueryLimit,
    );
  }

  Future<_BoundedDocuments> _loadDiscussionThreads(
    String trainerId,
    Set<String> athleteIds,
  ) async {
    final projectedFuture = _loadPerAthlete(
      athleteIds: athleteIds,
      perAthleteLimit: trainerDashboardPageSize,
      globalLimit: trainerDashboardPageSize,
      query: (athleteId) => _firestore
          .collection('workoutDiscussionThreads')
          .where('trainerId', isEqualTo: trainerId)
          .where('athleteId', isEqualTo: athleteId)
          .orderBy('lastActivityAt', descending: true),
      timestamp: (document) =>
          _optionalDateTime(document.data()['lastActivityAt']),
    );
    final fallbackFuture = _loadPerAthlete(
      athleteIds: athleteIds,
      perAthleteLimit: trainerDashboardPageSize,
      globalLimit: trainerDashboardPageSize,
      query: (athleteId) => _firestore
          .collection('workoutDiscussionThreads')
          .where('trainerId', isEqualTo: trainerId)
          .where('athleteId', isEqualTo: athleteId)
          .orderBy('completedAt', descending: true),
      timestamp: (document) =>
          _optionalDateTime(document.data()['completedAt']),
    );
    final projected = await projectedFuture;
    final fallback = await fallbackFuture;
    final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final document in fallback.documents) document.id: document,
      for (final document in projected.documents) document.id: document,
    }.values.toList();
    merged.sort((a, b) {
      final aTime = _optionalDateTime(a.data()['lastActivityAt']) ??
          _optionalDateTime(a.data()['completedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = _optionalDateTime(b.data()['lastActivityAt']) ??
          _optionalDateTime(b.data()['completedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final timeOrder = bTime.compareTo(aTime);
      return timeOrder != 0 ? timeOrder : a.id.compareTo(b.id);
    });
    return _BoundedDocuments(
      documents: List.unmodifiable(
        merged.take(trainerDashboardPageSize),
      ),
      hitLimit: projected.hitLimit ||
          fallback.hitLimit ||
          merged.length > trainerDashboardPageSize,
    );
  }

  Future<_BoundedDocuments> _loadEndingPrograms(
    String trainerId,
    Set<String> athleteIds,
    DateTime today,
    DateTime endingBoundary,
  ) {
    return _loadPerAthlete(
      athleteIds: athleteIds,
      perAthleteLimit: trainerDashboardPageSize,
      globalLimit: trainerDashboardPageSize,
      query: (athleteId) => _firestore
          .collection('athleteProgramInstances')
          .where('assigningTrainerId', isEqualTo: trainerId)
          .where('athleteOwnerId', isEqualTo: athleteId)
          .where('status', isEqualTo: 'active')
          .where(
            'expectedEndDate',
            isGreaterThanOrEqualTo: _formatDate(today),
          )
          .where(
            'expectedEndDate',
            isLessThanOrEqualTo: _formatDate(endingBoundary),
          )
          .orderBy('expectedEndDate'),
      timestamp: (document) =>
          _parseDate(document.data()['expectedEndDate'] as String?),
    );
  }

  Future<_BoundedDocuments> _loadPerAthlete({
    required Set<String> athleteIds,
    required int perAthleteLimit,
    required int globalLimit,
    required Query<Map<String, dynamic>> Function(String athleteId) query,
    required DateTime? Function(
      QueryDocumentSnapshot<Map<String, dynamic>> document,
    ) timestamp,
  }) async {
    final snapshots = await Future.wait(
      athleteIds.map(
        (athleteId) => query(athleteId).limit(perAthleteLimit).get(),
      ),
    );
    final documents = snapshots.expand((snapshot) => snapshot.docs).toList();
    documents.sort((a, b) {
      final aTime = timestamp(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = timestamp(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final timeOrder = bTime.compareTo(aTime);
      return timeOrder != 0 ? timeOrder : a.id.compareTo(b.id);
    });
    return _BoundedDocuments(
      documents: List.unmodifiable(documents.take(globalLimit)),
      hitLimit: documents.length > globalLimit ||
          snapshots.any(
            (snapshot) => snapshot.docs.length >= perAthleteLimit,
          ),
    );
  }

  Future<String> addQuickComment({
    required String trainerId,
    required String workoutInstanceId,
    required String body,
  }) async {
    _verifyAuthenticatedTrainer(trainerId);
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) {
      throw ArgumentError('Comment cannot be empty');
    }
    if (normalizedBody.length > 2000) {
      throw ArgumentError('Comment cannot exceed 2000 characters');
    }
    final thread = _firestore
        .collection('workoutDiscussionThreads')
        .doc(workoutInstanceId);
    final message = thread.collection('threadMessages').doc();

    await _firestore.runTransaction<void>((transaction) async {
      final context = await _verifyMutation(
        transaction: transaction,
        trainerId: trainerId,
        workoutInstanceId: workoutInstanceId,
      );
      final existingThread = await transaction.get(thread);
      if (!existingThread.exists) {
        transaction.set(thread, {
          'workoutInstanceId': workoutInstanceId,
          'athleteId': context.athleteId,
          'trainerId': trainerId,
          'completedAt': context.completedAt,
          'lastActivityAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': trainerId,
        });
      } else {
        if (existingThread.data()?['athleteId'] != context.athleteId ||
            existingThread.data()?['trainerId'] != trainerId ||
            existingThread.data()?['workoutInstanceId'] != workoutInstanceId) {
          throw StateError(
            'Discussion thread $workoutInstanceId ownership mismatch',
          );
        }
        transaction.update(thread, {
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(message, {
        'authorId': trainerId,
        'body': normalizedBody,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return message.id;
  }

  Future<bool> toggleReaction({
    required String trainerId,
    required String workoutInstanceId,
    required String reactionId,
  }) async {
    _verifyAuthenticatedTrainer(trainerId);
    CoachingReaction? definition;
    for (final reaction in coachingReactions) {
      if (reaction.id == reactionId) {
        definition = reaction;
        break;
      }
    }
    if (definition == null) {
      throw ArgumentError('Unsupported coaching reaction: $reactionId');
    }
    await _verifyMutationOutsideTransaction(
      trainerId: trainerId,
      workoutInstanceId: workoutInstanceId,
    );
    final thread = _firestore
        .collection('workoutDiscussionThreads')
        .doc(workoutInstanceId);
    final reactionState = await _loadTrainerReactionState(
      thread,
      trainerId,
    );
    if (reactionState.ownReactionReferences.isNotEmpty) {
      await _deleteTrainerReactions(
        trainerId: trainerId,
        workoutInstanceId: workoutInstanceId,
        references: reactionState.ownReactionReferences,
      );
      if (reactionState.currentReactionId == definition.id) {
        return false;
      }
    }
    await _createTrainerReaction(
      trainerId: trainerId,
      workoutInstanceId: workoutInstanceId,
      reactionId: definition.id,
      thread: thread,
      targetMessage: reactionState.targetMessage,
    );
    return true;
  }

  Future<void> _deleteTrainerReactions({
    required String trainerId,
    required String workoutInstanceId,
    required List<DocumentReference<Map<String, dynamic>>> references,
  }) {
    return _firestore.runTransaction<void>((transaction) async {
      await _verifyMutation(
        transaction: transaction,
        trainerId: trainerId,
        workoutInstanceId: workoutInstanceId,
      );
      final snapshots = await Future.wait(references.map(transaction.get));
      for (final snapshot in snapshots) {
        if (snapshot.exists && snapshot.data()?['actorId'] != trainerId) {
          throw StateError('Reaction ownership mismatch');
        }
      }
      for (final reference in references) {
        transaction.delete(reference);
      }
    });
  }

  Future<void> _createTrainerReaction({
    required String trainerId,
    required String workoutInstanceId,
    required String reactionId,
    required DocumentReference<Map<String, dynamic>> thread,
    required DocumentReference<Map<String, dynamic>> targetMessage,
  }) async {
    await _firestore.runTransaction<void>((transaction) async {
      final context = await _verifyMutation(
        transaction: transaction,
        trainerId: trainerId,
        workoutInstanceId: workoutInstanceId,
      );
      final existingThread = await transaction.get(thread);
      final existingTargetMessage = await transaction.get(targetMessage);
      if (!existingThread.exists) {
        transaction.set(thread, {
          'workoutInstanceId': workoutInstanceId,
          'athleteId': context.athleteId,
          'trainerId': trainerId,
          'completedAt': context.completedAt,
          'lastActivityAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': trainerId,
        });
      } else {
        if (existingThread.data()?['athleteId'] != context.athleteId ||
            existingThread.data()?['trainerId'] != trainerId ||
            existingThread.data()?['workoutInstanceId'] != workoutInstanceId) {
          throw StateError(
            'Discussion thread $workoutInstanceId ownership mismatch',
          );
        }
        transaction.update(thread, {
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      }
      if (!existingTargetMessage.exists) {
        transaction.set(targetMessage, {
          'authorId': trainerId,
          'body': 'Workout completion',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(targetMessage.collection('reactions').doc(trainerId), {
        'actorId': trainerId,
        'reactionId': reactionId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _verifyMutationOutsideTransaction({
    required String trainerId,
    required String workoutInstanceId,
  }) async {
    final workout = await _firestore
        .collection('workoutInstances')
        .doc(workoutInstanceId)
        .get();
    if (!workout.exists || workout.data() == null) {
      throw StateError('Workout instance $workoutInstanceId not found');
    }
    final data = workout.data()!;
    final athleteId = data['athleteId'] as String? ?? '';
    final programId = data['programId'] as String? ?? '';
    if (data['programOwnerId'] != trainerId) {
      throw StateError(
        'User $trainerId does not own workout $workoutInstanceId',
      );
    }
    if (data['status'] != 'completed' || data['completedAt'] == null) {
      throw StateError('Coaching interactions require a completed workout');
    }
    if (athleteId.isEmpty || programId.isEmpty) {
      throw StateError('Workout $workoutInstanceId has invalid ownership data');
    }
    final results = await Future.wait([
      _firestore.collection('programs').doc(programId).get(),
      _firestore
          .collection('trainerClientRelationships')
          .doc('${trainerId}_$athleteId')
          .get(),
    ]);
    final program = results[0];
    final relationship = results[1];
    if (!program.exists || program.data()?['ownerId'] != trainerId) {
      throw StateError(
        'User $trainerId is not the owner of program $programId',
      );
    }
    if (!relationship.exists ||
        relationship.data()?['trainerId'] != trainerId ||
        relationship.data()?['athleteId'] != athleteId ||
        relationship.data()?['status'] != 'active') {
      throw StateError(
        'Trainer $trainerId has no active relationship with $athleteId',
      );
    }
  }

  Future<_TrainerReactionState> _loadTrainerReactionState(
    DocumentReference<Map<String, dynamic>> thread,
    String trainerId,
  ) async {
    final threadSnapshot = await thread.get();
    if (!threadSnapshot.exists) {
      return _TrainerReactionState(
        targetMessage: thread
            .collection('threadMessages')
            .doc(_completionActivityMessageId),
        ownReactionReferences: const [],
        currentReactionId: null,
      );
    }
    final messages = await thread
        .collection('threadMessages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    final realMessages = messages.docs
        .where((message) => message.id != _completionActivityMessageId)
        .toList();
    final targetMessage = realMessages.isEmpty
        ? thread.collection('threadMessages').doc(_completionActivityMessageId)
        : realMessages.first.reference;
    final references = <DocumentReference<Map<String, dynamic>>>[];
    String? currentReactionId;
    for (final message in messages.docs) {
      final reference =
          message.reference.collection('reactions').doc(trainerId);
      final snapshot = await reference.get();
      if (snapshot.exists) {
        references.add(reference);
        currentReactionId ??= snapshot.data()?['reactionId'] as String?;
      }
    }
    return _TrainerReactionState(
      targetMessage: targetMessage,
      ownReactionReferences: List.unmodifiable(references),
      currentReactionId: currentReactionId,
    );
  }

  Future<_MutationContext> _verifyMutation({
    required Transaction transaction,
    required String trainerId,
    required String workoutInstanceId,
  }) async {
    final workoutRef =
        _firestore.collection('workoutInstances').doc(workoutInstanceId);
    final workout = await transaction.get(workoutRef);
    if (!workout.exists || workout.data() == null) {
      throw StateError('Workout instance $workoutInstanceId not found');
    }
    final data = workout.data()!;
    final athleteId = data['athleteId'] as String? ?? '';
    final programId = data['programId'] as String? ?? '';
    final completedAt = data['completedAt'];
    if (data['programOwnerId'] != trainerId) {
      throw StateError(
        'User $trainerId does not own workout $workoutInstanceId',
      );
    }
    if (data['status'] != 'completed' || completedAt == null) {
      throw StateError('Coaching interactions require a completed workout');
    }
    if (athleteId.isEmpty || programId.isEmpty) {
      throw StateError('Workout $workoutInstanceId has invalid ownership data');
    }
    final programRef = _firestore.collection('programs').doc(programId);
    final relationshipRef = _firestore
        .collection('trainerClientRelationships')
        .doc('${trainerId}_$athleteId');
    final program = await transaction.get(programRef);
    final relationship = await transaction.get(relationshipRef);
    if (!program.exists || program.data()?['ownerId'] != trainerId) {
      throw StateError(
        'User $trainerId is not the owner of program $programId',
      );
    }
    if (!relationship.exists ||
        relationship.data()?['trainerId'] != trainerId ||
        relationship.data()?['athleteId'] != athleteId ||
        relationship.data()?['status'] != 'active') {
      throw StateError(
        'Trainer $trainerId has no active relationship with $athleteId',
      );
    }
    return _MutationContext(
      athleteId: athleteId,
      programId: programId,
      completedAt: completedAt,
    );
  }

  Future<Map<String, String>> _loadNames(Iterable<String> userIds) async {
    final result = <String, String>{};
    for (final userId in userIds) {
      result[userId] = await _loadDocumentName('users', userId, 'Athlete');
    }
    return result;
  }

  Future<String> _loadDocumentName(
    String collection,
    String id,
    String fallback,
  ) async {
    if (id.isEmpty) {
      return fallback;
    }
    final snapshot = await _firestore.collection(collection).doc(id).get();
    final name = snapshot.data()?['name'] as String? ??
        snapshot.data()?['displayName'] as String?;
    return name == null || name.trim().isEmpty ? fallback : name.trim();
  }

  void _verifyAuthenticatedTrainer(String trainerId) {
    if (trainerId.trim().isEmpty) {
      throw StateError('An authenticated trainer is required');
    }
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static DateTime? _optionalDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static CoachingReaction? _reactionForId(String reactionId) {
    for (final reaction in coachingReactions) {
      if (reaction.id == reactionId) {
        return reaction;
      }
    }
    return null;
  }
}

class _MutationContext {
  const _MutationContext({
    required this.athleteId,
    required this.programId,
    required this.completedAt,
  });

  final String athleteId;
  final String programId;
  final Object completedAt;
}

class _DiscussionSummary {
  const _DiscussionSummary({
    required this.latestComment,
    required this.reactionCounts,
    required this.currentTrainerReaction,
  });

  final String? latestComment;
  final Map<String, int> reactionCounts;
  final String? currentTrainerReaction;
}

class _BoundedDocuments {
  const _BoundedDocuments({
    required this.documents,
    required this.hitLimit,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> documents;
  final bool hitLimit;
}

class _TrainerReactionState {
  const _TrainerReactionState({
    required this.targetMessage,
    required this.ownReactionReferences,
    required this.currentReactionId,
  });

  final DocumentReference<Map<String, dynamic>> targetMessage;
  final List<DocumentReference<Map<String, dynamic>>> ownReactionReferences;
  final String? currentReactionId;
}

class _DiscussionActivityLoad {
  const _DiscussionActivityLoad({
    required this.events,
    required this.summaries,
    required this.hitLimit,
  });

  final List<TrainerActivityEvent> events;
  final Map<String, _DiscussionSummary> summaries;
  final bool hitLimit;
}
