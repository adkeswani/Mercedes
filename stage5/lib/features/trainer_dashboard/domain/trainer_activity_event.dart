enum TrainerActivityEventType {
  completion,
  comment,
  reaction,
  programEndingSoon,
  personalBest,
}

enum TrainerActivityFilter {
  all,
  completions,
  comments,
  reactions,
  programs,
  personalBests,
}

const int trainerProgramEndingSoonDays = 7;
const int trainerDashboardPageSize = 50;
const int trainerDashboardCompletionQueryLimit = 40;
const int trainerDashboardInteractionQueryLimit = 40;
const int trainerDashboardRelationshipQueryLimit = 50;

const String trainerDashboardEmptyCanaryContent =
    'Trainer dashboard | No recent client activity';

const List<CoachingReaction> coachingReactions = [
  CoachingReaction(id: 'celebrate', symbol: '🎉', label: 'Celebrate'),
  CoachingReaction(id: 'strong', symbol: '💪', label: 'Strong work'),
  CoachingReaction(id: 'progress', symbol: '📈', label: 'Great progress'),
  CoachingReaction(id: 'support', symbol: '👏', label: 'Applaud'),
];

class CoachingReaction {
  const CoachingReaction({
    required this.id,
    required this.symbol,
    required this.label,
  });

  final String id;
  final String symbol;
  final String label;
}

abstract class TrainerActivityEvent {
  const TrainerActivityEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.athleteId,
    required this.athleteName,
  });

  final String id;
  final TrainerActivityEventType type;
  final DateTime occurredAt;
  final String athleteId;
  final String athleteName;
}

class CompletionActivityEvent extends TrainerActivityEvent {
  const CompletionActivityEvent({
    required super.id,
    required super.occurredAt,
    required super.athleteId,
    required super.athleteName,
    required this.workoutInstanceId,
    required this.workoutName,
    required this.programId,
    required this.rpe,
    required this.durationMinutes,
    required this.reactionCounts,
    this.latestComment,
    this.currentTrainerReaction,
  }) : super(type: TrainerActivityEventType.completion);

  final String workoutInstanceId;
  final String workoutName;
  final String programId;
  final int rpe;
  final int durationMinutes;
  final String? latestComment;
  final Map<String, int> reactionCounts;
  final String? currentTrainerReaction;
}

class CommentActivityEvent extends TrainerActivityEvent {
  const CommentActivityEvent({
    required super.id,
    required super.occurredAt,
    required super.athleteId,
    required super.athleteName,
    required this.workoutInstanceId,
    required this.comment,
    required this.authorName,
  }) : super(type: TrainerActivityEventType.comment);

  final String workoutInstanceId;
  final String comment;
  final String authorName;
}

class ReactionActivityEvent extends TrainerActivityEvent {
  const ReactionActivityEvent({
    required super.id,
    required super.occurredAt,
    required super.athleteId,
    required super.athleteName,
    required this.workoutInstanceId,
    required this.reactionId,
    required this.actorName,
  }) : super(type: TrainerActivityEventType.reaction);

  final String workoutInstanceId;
  final String reactionId;
  final String actorName;
}

class ProgramEndingSoonActivityEvent extends TrainerActivityEvent {
  const ProgramEndingSoonActivityEvent({
    required super.id,
    required super.occurredAt,
    required super.athleteId,
    required super.athleteName,
    required this.programInstanceId,
    required this.programId,
    required this.programName,
    required this.endDate,
    required this.daysRemaining,
  }) : super(type: TrainerActivityEventType.programEndingSoon);

  final String programInstanceId;
  final String programId;
  final String programName;
  final String endDate;
  final int daysRemaining;
}

class PersonalBestActivityEvent extends TrainerActivityEvent {
  const PersonalBestActivityEvent({
    required super.id,
    required super.occurredAt,
    required super.athleteId,
    required super.athleteName,
    required this.summary,
  }) : super(type: TrainerActivityEventType.personalBest);

  final String summary;
}

class TrainerDashboardPage {
  const TrainerDashboardPage({required this.events, required this.isBounded});

  final List<TrainerActivityEvent> events;
  final bool isBounded;
}

List<TrainerActivityEvent> filterTrainerActivityEvents(
  Iterable<TrainerActivityEvent> events,
  TrainerActivityFilter filter,
) {
  final type = switch (filter) {
    TrainerActivityFilter.all => null,
    TrainerActivityFilter.completions => TrainerActivityEventType.completion,
    TrainerActivityFilter.comments => TrainerActivityEventType.comment,
    TrainerActivityFilter.reactions => TrainerActivityEventType.reaction,
    TrainerActivityFilter.programs =>
      TrainerActivityEventType.programEndingSoon,
    TrainerActivityFilter.personalBests =>
      TrainerActivityEventType.personalBest,
  };
  if (type == null) {
    return List.unmodifiable(events);
  }
  return List.unmodifiable(events.where((event) => event.type == type));
}

int calendarDaysRemaining(DateTime now, DateTime endDate) {
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  return end.difference(today).inDays;
}

String trainerDashboardCanaryContentFor(
  Iterable<TrainerActivityEvent> events,
) {
  final ordered = events.toList()
    ..sort((a, b) {
      final timeOrder = b.occurredAt.compareTo(a.occurredAt);
      return timeOrder != 0 ? timeOrder : a.id.compareTo(b.id);
    });
  final completions = {
    for (final completion in ordered.whereType<CompletionActivityEvent>())
      completion.workoutInstanceId: completion,
  };
  final parts = <String>[];
  for (final event in ordered) {
    if (event is ReactionActivityEvent) {
      final definition = coachingReactions.firstWhere(
        (reaction) => reaction.id == event.reactionId,
      );
      final count = completions[event.workoutInstanceId]
              ?.reactionCounts[event.reactionId] ??
          1;
      parts.add('Reaction: ${definition.symbol} $count');
    } else if (event is CommentActivityEvent) {
      parts.add('Comment: ${event.comment}');
    } else if (event is CompletionActivityEvent) {
      parts.add('Completion: ${event.workoutName}');
    } else if (event is ProgramEndingSoonActivityEvent) {
      final unit = event.daysRemaining == 1 ? 'day' : 'days';
      parts.add(
        'Program ending soon: ${event.programName} '
        '(${event.daysRemaining} $unit)',
      );
    }
  }
  if (parts.isEmpty) {
    return trainerDashboardEmptyCanaryContent;
  }
  return parts.join(' | ');
}
