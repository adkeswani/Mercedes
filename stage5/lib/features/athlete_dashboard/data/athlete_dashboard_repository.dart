import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/features/athlete_dashboard/domain/athlete_activity_event.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart'
    show CoachingReaction, coachingReactions;

/// Loads a single athlete's own completions, comments, and reactions from
/// their completed-workout discussion threads.
///
/// This mirrors `TrainerDashboardRepository`'s discussion-loading approach,
/// but is scoped to one `athleteId` (no cross-athlete relationship fan-out
/// is needed) and is read-only: posting comments/reactions from the athlete
/// side is not yet implemented.
class AthleteDashboardRepository {
  AthleteDashboardRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const _completionActivityMessageId = 'completion-activity';

  Future<AthleteDashboardPage> loadInitialPage(String athleteId) async {
    _verifyAuthenticatedAthlete(athleteId);

    final completionsFuture = _loadCompletions(athleteId);
    final discussionsFuture = _loadDiscussionActivities(athleteId);
    final completions = await completionsFuture;
    final discussions = await discussionsFuture;

    final events = <AthleteActivityEvent>[];

    for (final completion in completions.documents) {
      final data = completion.data();
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
      events.add(
        AthleteCompletionActivityEvent(
          id: 'completion:${completion.id}',
          occurredAt: completedAt,
          workoutInstanceId: completion.id,
          workoutName: workoutName,
          rpe: (data['rpe'] as num?)?.toInt() ?? 0,
          durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    events.addAll(discussions.events);

    events.sort((a, b) {
      final dateOrder = b.occurredAt.compareTo(a.occurredAt);
      return dateOrder != 0 ? dateOrder : a.id.compareTo(b.id);
    });

    final isBounded = events.length > athleteDashboardPageSize ||
        completions.hitLimit ||
        discussions.hitLimit;

    return AthleteDashboardPage(
      events: List.unmodifiable(events.take(athleteDashboardPageSize)),
      isBounded: isBounded,
    );
  }

  Future<_BoundedDocuments> _loadCompletions(String athleteId) async {
    final snapshot = await _firestore
        .collection('workoutInstances')
        .where('athleteId', isEqualTo: athleteId)
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .limit(athleteDashboardCompletionQueryLimit)
        .get();
    return _BoundedDocuments(
      documents: List.unmodifiable(snapshot.docs),
      hitLimit: snapshot.docs.length >= athleteDashboardCompletionQueryLimit,
    );
  }

  Future<_DiscussionActivityLoad> _loadDiscussionActivities(
    String athleteId,
  ) async {
    final threads = await _loadDiscussionThreads(athleteId);
    final events = <AthleteActivityEvent>[];
    var hitLimit = threads.hitLimit;

    for (final thread in threads.documents) {
      final data = thread.data();
      if (data['athleteId'] != athleteId ||
          data['workoutInstanceId'] != thread.id) {
        continue;
      }
      final messages = await thread.reference
          .collection('threadMessages')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      if (messages.docs.length >= 100) {
        hitLimit = true;
      }
      for (final message in messages.docs) {
        final isCompletionAnchor = message.id == _completionActivityMessageId;
        final body = (message.data()['body'] as String? ?? '').trim();
        final messageAt = _optionalDateTime(message.data()['createdAt']);
        final authorId = message.data()['authorId'] as String? ?? '';
        if (!isCompletionAnchor && body.isNotEmpty && messageAt != null) {
          events.add(
            AthleteCommentActivityEvent(
              id: 'comment:${thread.id}:${message.id}',
              occurredAt: messageAt,
              workoutInstanceId: thread.id,
              comment: body,
              authorName: authorId == athleteId ? 'You' : 'Coach',
            ),
          );
        }
        final reactions = await message.reference
            .collection('reactions')
            .limit(100)
            .get();
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
          events.add(
            AthleteReactionActivityEvent(
              id: 'reaction:${thread.id}:${message.id}:${reaction.id}',
              occurredAt: reactionAt,
              workoutInstanceId: thread.id,
              reactionId: definition.id,
              actorName: actorId == athleteId ? 'You' : 'Coach',
            ),
          );
        }
      }
    }

    events.sort((a, b) {
      final timeOrder = b.occurredAt.compareTo(a.occurredAt);
      return timeOrder != 0 ? timeOrder : a.id.compareTo(b.id);
    });

    return _DiscussionActivityLoad(
      events: List.unmodifiable(
        events.take(athleteDashboardInteractionQueryLimit),
      ),
      hitLimit:
          hitLimit || events.length > athleteDashboardInteractionQueryLimit,
    );
  }

  Future<_BoundedDocuments> _loadDiscussionThreads(String athleteId) async {
    final projected = await _firestore
        .collection('workoutDiscussionThreads')
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('lastActivityAt', descending: true)
        .limit(athleteDashboardPageSize)
        .get();
    final fallback = await _firestore
        .collection('workoutDiscussionThreads')
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('completedAt', descending: true)
        .limit(athleteDashboardPageSize)
        .get();
    final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final document in fallback.docs) document.id: document,
      for (final document in projected.docs) document.id: document,
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
      documents: List.unmodifiable(merged.take(athleteDashboardPageSize)),
      hitLimit: projected.docs.length >= athleteDashboardPageSize ||
          fallback.docs.length >= athleteDashboardPageSize ||
          merged.length > athleteDashboardPageSize,
    );
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
    final name = snapshot.data()?['name'] as String?;
    return name == null || name.trim().isEmpty ? fallback : name.trim();
  }

  void _verifyAuthenticatedAthlete(String athleteId) {
    if (athleteId.trim().isEmpty) {
      throw StateError('An authenticated athlete is required');
    }
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

class _BoundedDocuments {
  const _BoundedDocuments({required this.documents, required this.hitLimit});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> documents;
  final bool hitLimit;
}

class _DiscussionActivityLoad {
  const _DiscussionActivityLoad({required this.events, required this.hitLimit});

  final List<AthleteActivityEvent> events;
  final bool hitLimit;
}
