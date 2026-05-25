import 'package:stage3/core/enums.dart';
import 'package:stage3/features/auth/domain/foundation_models.dart';

/// Workout template header with versioning support.
///
/// The template holds shared metadata. Each publish creates an immutable
/// [WorkoutTemplateVersion] sub-document. Old versions are never mutated.
///
/// A newly created template has [currentVersion] = 0 (no published versions).
class WorkoutTemplate with Auditable {

  WorkoutTemplate({
    required this.id,
    required this.name,
    required this.workoutType,
    required this.currentVersion,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.deletedAt,
    this.deletedBy,
  });

  final String id;
  final String name;
  final WorkoutType workoutType;
  final int currentVersion;
  @override
  final DateTime createdAt;
  @override
  final String createdBy;
  @override
  final DateTime updatedAt;
  @override
  final String updatedBy;
  @override
  final DateTime? deletedAt;
  @override
  final String? deletedBy;

  /// Whether this template has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Whether at least one version has been published.
  bool get hasPublishedVersion => currentVersion >= 1;

  /// Creates a copy with the given fields replaced.
  WorkoutTemplate copyWith({
    String? id,
    String? name,
    WorkoutType? workoutType,
    int? currentVersion,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return WorkoutTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      workoutType: workoutType ?? this.workoutType,
      currentVersion: currentVersion ?? this.currentVersion,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
    );
  }

  /// Validates all required fields and audit timestamp ordering.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (name.isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    if (currentVersion < 0) {
      throw ArgumentError('currentVersion must be >= 0');
    }
    if (createdBy.isEmpty) {
      throw ArgumentError('createdBy cannot be empty');
    }
    if (updatedBy.isEmpty) {
      throw ArgumentError('updatedBy cannot be empty');
    }
    Auditable.validateTimestamps(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

/// Immutable snapshot of a workout template at a specific version.
///
/// Each publish creates a new version document. Workout instances and
/// program mappings reference a specific (workoutTemplateId, versionNumber)
/// pair to preserve historical accuracy.
class WorkoutTemplateVersion {

  WorkoutTemplateVersion({
    required this.versionNumber,
    required this.publishedAt,
    required this.exercises,
    this.childWorkouts = const [],
  });

  final int versionNumber;
  final DateTime publishedAt;
  final List<ExercisePrescription> exercises;
  final List<ChildWorkoutRef> childWorkouts;

  /// Creates a copy with the given fields replaced.
  WorkoutTemplateVersion copyWith({
    int? versionNumber,
    DateTime? publishedAt,
    List<ExercisePrescription>? exercises,
    List<ChildWorkoutRef>? childWorkouts,
  }) {
    return WorkoutTemplateVersion(
      versionNumber: versionNumber ?? this.versionNumber,
      publishedAt: publishedAt ?? this.publishedAt,
      exercises: exercises ?? this.exercises,
      childWorkouts: childWorkouts ?? this.childWorkouts,
    );
  }

  /// Validates version fields.
  void validate() {
    if (versionNumber < 1) {
      throw ArgumentError('versionNumber must be >= 1');
    }

    for (final exercise in exercises) {
      exercise.validate();
    }

    for (final child in childWorkouts) {
      child.validate();
    }

    // Validate sort order uniqueness within exercises
    final exerciseSorts = exercises.map((e) => e.sortOrder).toSet();
    if (exerciseSorts.length != exercises.length) {
      throw ArgumentError(
        'Exercise sortOrder values must be unique within a version',
      );
    }

    // Validate sort order uniqueness within child workouts
    final childSorts = childWorkouts.map((c) => c.sortOrder).toSet();
    if (childSorts.length != childWorkouts.length) {
      throw ArgumentError(
        'Child workout sortOrder values must be unique within a version',
      );
    }
  }
}

/// An exercise slot within a workout template version.
///
/// Holds the exercise reference, display order, and prescription details
/// (sets, reps, duration, weight, rest, notes).
///
/// [exerciseName] is denormalized at publish time for historical stability —
/// even if the exercise template is later renamed or deleted, published
/// versions retain the name as it was when published.
class ExercisePrescription {

  ExercisePrescription({
    required this.exerciseId,
    required this.sortOrder,
    required this.mode,
    this.exerciseName,
    this.sets,
    this.reps,
    this.durationSeconds,
    this.weight,
    this.restSeconds,
    this.notes,
  });

  final String exerciseId;
  final int sortOrder;
  final ExerciseMode mode;
  final String? exerciseName;
  final int? sets;
  final String? reps;
  final int? durationSeconds;
  final String? weight;
  final int? restSeconds;
  final String? notes;

  /// Creates a copy with the given fields replaced.
  ExercisePrescription copyWith({
    String? exerciseId,
    int? sortOrder,
    ExerciseMode? mode,
    String? exerciseName,
    int? sets,
    String? reps,
    int? durationSeconds,
    String? weight,
    int? restSeconds,
    String? notes,
  }) {
    return ExercisePrescription(
      exerciseId: exerciseId ?? this.exerciseId,
      sortOrder: sortOrder ?? this.sortOrder,
      mode: mode ?? this.mode,
      exerciseName: exerciseName ?? this.exerciseName,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      weight: weight ?? this.weight,
      restSeconds: restSeconds ?? this.restSeconds,
      notes: notes ?? this.notes,
    );
  }

  /// Validates prescription fields.
  void validate() {
    if (exerciseId.isEmpty) {
      throw ArgumentError('exerciseId cannot be empty');
    }
    if (sortOrder < 0) {
      throw ArgumentError('sortOrder must be >= 0');
    }
    if (sets != null && sets! < 1) {
      throw ArgumentError('sets must be >= 1 when provided');
    }
    if (durationSeconds != null && durationSeconds! < 1) {
      throw ArgumentError('durationSeconds must be >= 1 when provided');
    }
    if (restSeconds != null && restSeconds! < 0) {
      throw ArgumentError('restSeconds must be >= 0 when provided');
    }
  }
}

/// Reference to a nested child workout within a parent workout template.
///
/// Supports one level of nesting in the MVP UI (parent → children),
/// though the data model allows deeper nesting.
class ChildWorkoutRef {

  ChildWorkoutRef({
    required this.workoutTemplateId,
    required this.versionNumber,
    required this.sortOrder,
  });

  final String workoutTemplateId;
  final int versionNumber;
  final int sortOrder;

  /// Validates reference fields.
  void validate() {
    if (workoutTemplateId.isEmpty) {
      throw ArgumentError('workoutTemplateId cannot be empty');
    }
    if (versionNumber < 1) {
      throw ArgumentError('versionNumber must be >= 1');
    }
    if (sortOrder < 0) {
      throw ArgumentError('sortOrder must be >= 0');
    }
  }
}
