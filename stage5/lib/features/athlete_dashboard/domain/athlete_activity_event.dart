enum AthleteActivityEventType { completion, comment, reaction }

/// "Today's workouts" is handled by a dedicated schedule-backed view rather
/// than the activity feed, so it isn't an [AthleteActivityEventType].
enum AthleteActivityFilter { all, todaysWorkouts, completed, comments, reactions }

const int athleteDashboardPageSize = 50;
const int athleteDashboardCompletionQueryLimit = 40;
const int athleteDashboardInteractionQueryLimit = 40;

/// How far back the dashboard queries for activity, for every tab except
/// Today's Workouts (which is always scoped to the current day). Keeping
/// this a fixed window instead of a user-facing range picker keeps the
/// feature simple while still bounding query cost.
const int athleteDashboardQueryWindowDays = 7;

const String athleteDashboardEmptyCanaryContent =
    'Athlete dashboard | No recent activity';

abstract class AthleteActivityEvent {
  const AthleteActivityEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
  });

  final String id;
  final AthleteActivityEventType type;
  final DateTime occurredAt;
}

class AthleteCompletionActivityEvent extends AthleteActivityEvent {
  const AthleteCompletionActivityEvent({
    required super.id,
    required super.occurredAt,
    required this.workoutInstanceId,
    required this.workoutName,
    required this.rpe,
    required this.durationMinutes,
  }) : super(type: AthleteActivityEventType.completion);

  final String workoutInstanceId;
  final String workoutName;
  final int rpe;
  final int durationMinutes;
}

class AthleteCommentActivityEvent extends AthleteActivityEvent {
  const AthleteCommentActivityEvent({
    required super.id,
    required super.occurredAt,
    required this.workoutInstanceId,
    required this.comment,
    required this.authorName,
  }) : super(type: AthleteActivityEventType.comment);

  final String workoutInstanceId;
  final String comment;
  final String authorName;
}

class AthleteReactionActivityEvent extends AthleteActivityEvent {
  const AthleteReactionActivityEvent({
    required super.id,
    required super.occurredAt,
    required this.workoutInstanceId,
    required this.reactionId,
    required this.actorName,
  }) : super(type: AthleteActivityEventType.reaction);

  final String workoutInstanceId;
  final String reactionId;
  final String actorName;
}

class AthleteDashboardPage {
  const AthleteDashboardPage({required this.events, required this.isBounded});

  final List<AthleteActivityEvent> events;
  final bool isBounded;
}

/// Filters the activity feed for the All/Comments/Reactions tabs. The
/// Today's Workouts tab does not use this feed and is handled separately.
List<AthleteActivityEvent> filterAthleteActivityEvents(
  Iterable<AthleteActivityEvent> events,
  AthleteActivityFilter filter,
) {
  final type = switch (filter) {
    AthleteActivityFilter.all => null,
    AthleteActivityFilter.todaysWorkouts => null,
    AthleteActivityFilter.completed => AthleteActivityEventType.completion,
    AthleteActivityFilter.comments => AthleteActivityEventType.comment,
    AthleteActivityFilter.reactions => AthleteActivityEventType.reaction,
  };
  if (type == null) {
    return List.unmodifiable(events);
  }
  return List.unmodifiable(events.where((event) => event.type == type));
}
