/// Shared enumerations for the domain model.
///
/// All enums used across multiple model files are defined here
/// to avoid circular dependencies and provide a single source of truth.
library;

/// Workout type classifies what a session trains.
///
/// The coach sets the workout type on the Workout Template,
/// and logged instances inherit that assigned type.
enum WorkoutType {
  // Climbing types
  limit,
  power,
  powerEndurance,
  endurance,
  skill,
  mobility,
  cardio,

  // Strength types
  lower,
  upper,
  fullBody,
  pull,
  push,
  legs,
  core,
  conditioning,
}

/// Program lifecycle status.
enum ProgramStatus { draft, published, archived }

/// Whether a program is owner-assignable or athlete-personal.
enum ProgramType { assignable, personal }

/// Enrollment lifecycle status.
enum EnrollmentStatus { active, removed }

/// Trainer-client relationship lifecycle status.
enum TrainerClientRelationshipStatus { active, ending, ended }

/// Whether an athlete program instance remains linked to its source template.
enum ProgramRelationshipMode { subscribed, copied }

/// Lifecycle of a materialized athlete program instance.
enum AthleteProgramInstanceStatus { active, completed, cancelled }

/// Recoverable server-side propagation lifecycle for a subscribed program.
enum ProgramPropagationState { pending, running, complete, failed }

/// Workout instance lifecycle status.
enum WorkoutInstanceStatus { scheduled, completed, missed, cancelled }

/// Exercise prescription mode.
enum ExerciseMode { reps, time, amrap }

/// Recurrence scheduling pattern.
enum RecurrencePattern { weekly, biweekly, custom }

/// Notification types that trigger in-app alerts.
enum NotificationType {
  comment,
  message,
  enrollment,
  workoutAssigned,
  missedWorkout,
  templateUpdated,
}

/// In-app feedback category.
enum FeedbackType { bug, feature, general }

/// Admin triage status for feedback items.
enum FeedbackStatus { newItem, reviewed, resolved, wontFix }

/// Schema backfill status for data evolution tracking.
enum BackfillStatus { pending, running, complete, notNeeded }
