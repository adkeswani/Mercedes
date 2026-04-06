import 'package:foundation_stage1/enums.dart';

/// A specific workout assigned to an athlete on a date.
///
/// Created from a workout template at schedule time. Tracks completion,
/// load metrics, recurrence, and per-exercise actuals. Completed
/// instances are immutable historical records.
class WorkoutInstance {

  WorkoutInstance({
    required this.id,
    required this.programId,
    required this.athleteId,
    required this.workoutTemplateId,
    required this.workoutTemplateVersion,
    required this.scheduledDate,
    required this.assignedBy,
    required this.assignedAt,
    required this.status,
    required this.workoutType,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.missedAt,
    this.rpe,
    this.durationMinutes,
    this.loadPoints,
    this.loadPointsOverride,
    this.loadPointsOverriddenBy,
    this.loadPointsOverriddenAt,
    this.loadModelVersion = 1,
    this.loadStrategyId,
    this.recurrence,
    this.isRecurrenceRoot = false,
    this.recurrenceRootId,
    this.actuals = const [],
    this.athleteNotes,
  });

  final String id;
  final String programId;
  final String athleteId;
  final String workoutTemplateId;
  final int workoutTemplateVersion;
  final String scheduledDate;
  final String assignedBy;
  final DateTime assignedAt;
  final WorkoutInstanceStatus status;
  final DateTime? completedAt;
  final DateTime? missedAt;
  final int? rpe;
  final int? durationMinutes;
  final double? loadPoints;

  /// Manual load override set by the program owner or athlete.
  ///
  /// When present, takes precedence over the computed [loadPoints]
  /// in dashboard queries and aggregations. The computed value is
  /// preserved so the override can be removed.
  final double? loadPointsOverride;

  /// Who set the load override (userId).
  final String? loadPointsOverriddenBy;

  /// When the load override was set.
  final DateTime? loadPointsOverriddenAt;

  final int loadModelVersion;

  /// Which load strategy produced the computed [loadPoints].
  ///
  /// Null means the default strategy was used. Stored for audit
  /// so historical values remain interpretable.
  final String? loadStrategyId;

  final WorkoutType workoutType;
  final Recurrence? recurrence;
  final bool isRecurrenceRoot;
  final String? recurrenceRootId;
  final List<ExerciseActual> actuals;
  final String? athleteNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether this instance has been completed by the athlete.
  bool get isCompleted => status == WorkoutInstanceStatus.completed;

  /// Whether this instance was marked as missed.
  bool get isMissed => status == WorkoutInstanceStatus.missed;

  /// Whether this instance is still scheduled (not yet completed or missed).
  bool get isScheduled => status == WorkoutInstanceStatus.scheduled;

  /// The effective load points value for dashboards and aggregations.
  ///
  /// Returns [loadPointsOverride] if the owner has set a manual override,
  /// otherwise returns the computed [loadPoints].
  double? get effectiveLoadPoints => loadPointsOverride ?? loadPoints;

  /// Whether the load points have been manually overridden.
  bool get isLoadOverridden => loadPointsOverride != null;

  /// Validates all required fields and business rules.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (programId.isEmpty) {
      throw ArgumentError('programId cannot be empty');
    }
    if (athleteId.isEmpty) {
      throw ArgumentError('athleteId cannot be empty');
    }
    if (workoutTemplateId.isEmpty) {
      throw ArgumentError('workoutTemplateId cannot be empty');
    }
    if (workoutTemplateVersion < 1) {
      throw ArgumentError('workoutTemplateVersion must be >= 1');
    }
    if (scheduledDate.isEmpty) {
      throw ArgumentError('scheduledDate cannot be empty');
    }
    if (assignedBy.isEmpty) {
      throw ArgumentError('assignedBy cannot be empty');
    }

    // ISO 8601 date format validation (YYYY-MM-DD)
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(scheduledDate)) {
      throw ArgumentError(
        'scheduledDate must be ISO 8601 date format (YYYY-MM-DD)',
      );
    }

    // RPE validation (1–10, required on completion)
    if (status == WorkoutInstanceStatus.completed) {
      if (rpe == null) {
        throw ArgumentError('rpe is required when status is completed');
      }
      if (durationMinutes == null) {
        throw ArgumentError(
          'durationMinutes is required when status is completed',
        );
      }
      if (completedAt == null) {
        throw ArgumentError(
          'completedAt is required when status is completed',
        );
      }
    }

    if (rpe != null && (rpe! < 1 || rpe! > 10)) {
      throw ArgumentError('rpe must be between 1 and 10');
    }

    if (durationMinutes != null && durationMinutes! < 0) {
      throw ArgumentError('durationMinutes must be >= 0');
    }

    if (loadModelVersion < 1) {
      throw ArgumentError('loadModelVersion must be >= 1');
    }

    // Override audit: if override is set, who and when are required
    if (loadPointsOverride != null) {
      if (loadPointsOverriddenBy == null ||
          loadPointsOverriddenBy!.isEmpty) {
        throw ArgumentError(
          'loadPointsOverriddenBy is required when override is set',
        );
      }
      if (loadPointsOverriddenAt == null) {
        throw ArgumentError(
          'loadPointsOverriddenAt is required when override is set',
        );
      }
    }

    recurrence?.validate();

    for (final actual in actuals) {
      actual.validate();
    }
  }
}

/// Per-exercise completion data recorded by the athlete.
///
/// Captures what the athlete actually performed vs. the prescription,
/// including timer data for rest and work duration.
class ExerciseActual {

  ExerciseActual({
    required this.exerciseId,
    required this.mode,
    this.sets,
    this.reps,
    this.durationSeconds,
    this.weight,
    this.restSeconds,
    this.notes,
  });
  final String exerciseId;
  final ExerciseMode mode;
  final int? sets;
  final String? reps;
  final int? durationSeconds;
  final String? weight;
  final int? restSeconds;
  final String? notes;

  /// Validates actual fields.
  void validate() {
    if (exerciseId.isEmpty) {
      throw ArgumentError('exerciseId cannot be empty');
    }
    if (sets != null && sets! < 1) {
      throw ArgumentError('sets must be >= 1 when provided');
    }
    if (durationSeconds != null && durationSeconds! < 0) {
      throw ArgumentError('durationSeconds must be >= 0 when provided');
    }
    if (restSeconds != null && restSeconds! < 0) {
      throw ArgumentError('restSeconds must be >= 0 when provided');
    }
  }
}

/// Recurrence schedule for repeating workout assignments.
///
/// All recurrences are bounded (end date required). Instances are
/// materialized upfront via batch write — no open-ended recurrence.
class Recurrence {

  Recurrence({
    required this.pattern,
    required this.endDate, this.daysOfWeek,
    this.intervalDays,
  });
  final RecurrencePattern pattern;
  final List<int>? daysOfWeek;
  final int? intervalDays;
  final String endDate;

  /// Validates recurrence fields.
  void validate() {
    if (endDate.isEmpty) {
      throw ArgumentError('endDate cannot be empty');
    }

    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(endDate)) {
      throw ArgumentError(
        'endDate must be ISO 8601 date format (YYYY-MM-DD)',
      );
    }

    if (daysOfWeek != null) {
      for (final day in daysOfWeek!) {
        if (day < 1 || day > 7) {
          throw ArgumentError('daysOfWeek values must be 1-7 (Mon-Sun)');
        }
      }
    }

    if (intervalDays != null && intervalDays! < 1) {
      throw ArgumentError('intervalDays must be >= 1 when provided');
    }

    if (pattern == RecurrencePattern.custom && intervalDays == null) {
      throw ArgumentError(
        'intervalDays is required for custom recurrence pattern',
      );
    }
  }
}
