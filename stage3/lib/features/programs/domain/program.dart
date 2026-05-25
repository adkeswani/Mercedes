import 'package:stage3/core/enums.dart';
import 'package:stage3/features/auth/domain/foundation_models.dart';
import 'package:stage3/features/load/domain/load_model.dart';

/// A workout program with versioned structure.
///
/// Programs can be owner-assignable (enrollable athletes) or
/// athlete-personal (self-use only, non-assignable). Each publish
/// creates an immutable [ProgramVersion] snapshot.
///
/// Programs may customize load computation via [typeWeightOverrides]
/// (per-type weight adjustments) and [loadStrategyId] (alternative
/// calculation formula).
class Program with Auditable {

  Program({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.type,
    required this.status,
    required this.currentVersion,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.description,
    this.typeWeightOverrides,
    this.loadStrategyId,
    this.deletedAt,
    this.deletedBy,
  });

  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final ProgramType type;
  final ProgramStatus status;
  final int currentVersion;

  /// Per-program type weight overrides for load computation.
  ///
  /// When set, these weights are merged over the strategy's defaults.
  /// For example, `{WorkoutType.power: 3}` would lower the power
  /// weight from the default 4 to 3 for this program only.
  final Map<WorkoutType, int>? typeWeightOverrides;

  /// Optional load strategy identifier.
  ///
  /// When null, the [DefaultLoadStrategy] is used. Set to a strategy
  /// name (e.g. "climbing_focused_v1") to use an alternative formula.
  final String? loadStrategyId;

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

  /// Whether this program has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Whether this is a draft that hasn't been published yet.
  bool get isDraft => status == ProgramStatus.draft;

  /// Whether this program is currently published and active.
  bool get isPublished => status == ProgramStatus.published;

  /// Whether athletes can be enrolled in this program.
  bool get isAssignable => type == ProgramType.assignable;

  /// Whether this program has custom load weights.
  bool get hasCustomLoadWeights =>
      typeWeightOverrides != null && typeWeightOverrides!.isNotEmpty;

  /// Creates a copy with the given fields replaced.
  Program copyWith({
    String? id,
    String? name,
    String? description,
    String? ownerId,
    ProgramType? type,
    ProgramStatus? status,
    int? currentVersion,
    Map<WorkoutType, int>? typeWeightOverrides,
    String? loadStrategyId,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return Program(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      type: type ?? this.type,
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      typeWeightOverrides: typeWeightOverrides ?? this.typeWeightOverrides,
      loadStrategyId: loadStrategyId ?? this.loadStrategyId,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
    );
  }

  /// Validates all required fields and business rules.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (name.isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    if (ownerId.isEmpty) {
      throw ArgumentError('ownerId cannot be empty');
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

    if (typeWeightOverrides != null) {
      LoadModel.validateTypeWeightOverrides(typeWeightOverrides!);
    }

    Auditable.validateTimestamps(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

/// Immutable snapshot of a program's structure at a specific version.
///
/// Each publish creates a new version document containing the ordered
/// workout list. Enrollments and workout instances reference the
/// (programId, programVersion) pair to preserve history.
class ProgramVersion {

  ProgramVersion({
    required this.versionNumber,
    required this.publishedAt,
    required this.workouts,
    this.changeNote,
  });
  final int versionNumber;
  final DateTime publishedAt;
  final List<ProgramWorkoutRef> workouts;
  final String? changeNote;

  /// Validates version fields.
  void validate() {
    if (versionNumber < 1) {
      throw ArgumentError('versionNumber must be >= 1');
    }

    for (final workout in workouts) {
      workout.validate();
    }

    // Validate sort order uniqueness
    final sorts = workouts.map((w) => w.sortOrder).toSet();
    if (sorts.length != workouts.length) {
      throw ArgumentError(
        'Workout sortOrder values must be unique within a program version',
      );
    }
  }
}

/// Reference to a workout template within a program version.
///
/// [workoutName] is denormalized at publish time for historical stability —
/// even if the workout template is later renamed or deleted, published
/// versions retain the name as it was when published.
class ProgramWorkoutRef {

  ProgramWorkoutRef({
    required this.workoutTemplateId,
    required this.workoutTemplateVersion,
    required this.sortOrder,
    this.workoutName,
  });
  final String workoutTemplateId;
  final int workoutTemplateVersion;
  final int sortOrder;
  final String? workoutName;

  /// Validates reference fields.
  void validate() {
    if (workoutTemplateId.isEmpty) {
      throw ArgumentError('workoutTemplateId cannot be empty');
    }
    if (workoutTemplateVersion < 1) {
      throw ArgumentError('workoutTemplateVersion must be >= 1');
    }
    if (sortOrder < 0) {
      throw ArgumentError('sortOrder must be >= 0');
    }
  }
}
