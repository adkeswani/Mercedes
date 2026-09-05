import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/domain/foundation_models.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';

export 'package:stage5/features/workouts/domain/workout_block.dart';

const maxExercisePrescriptionsPerWorkoutVersion =
    maxExerciseSlotsPerWorkoutVersion;

/// Workout template header with versioning support.
///
/// The template holds shared metadata. Each publish creates an immutable
/// [WorkoutTemplateVersion] sub-document. Old versions are never mutated.
///
/// A newly created template has [currentVersion] = 0 (no published versions).
class WorkoutTemplate with Auditable implements LibraryItem {
  WorkoutTemplate({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.workoutType,
    required this.currentVersion,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.tags = const [],
    this.folderId,
    this.provenance,
    this.deletedAt,
    this.deletedBy,
  });

  final String id;
  final String ownerId;
  final String name;
  final WorkoutType workoutType;
  final int currentVersion;
  @override
  final List<String> tags;
  @override
  final String? folderId;
  @override
  final TemplateProvenance? provenance;
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
    String? ownerId,
    String? name,
    WorkoutType? workoutType,
    int? currentVersion,
    List<String>? tags,
    String? folderId,
    TemplateProvenance? provenance,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return WorkoutTemplate(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      workoutType: workoutType ?? this.workoutType,
      currentVersion: currentVersion ?? this.currentVersion,
      tags: tags ?? this.tags,
      folderId: folderId ?? this.folderId,
      provenance: provenance ?? this.provenance,
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
    validateLibraryMetadata(
      tags: tags,
      folderId: folderId,
      provenance: provenance,
    );
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
    List<WorkoutBlock>? blocks,
    List<ExerciseSlot>? exercises,
    this.childWorkouts = const [],
  })  : assert(blocks == null || exercises == null),
        blocks = blocks ?? legacyStandardBlocksFromSlots(exercises ?? const []);

  final int versionNumber;
  final DateTime publishedAt;
  final List<WorkoutBlock> blocks;
  final List<ChildWorkoutRef> childWorkouts;

  List<ExerciseSlot> get exerciseSlots => [
        for (final block in blocks)
          for (final slot in block.slots) slot,
      ];

  @Deprecated('Use blocks or exerciseSlots.')
  List<ExerciseSlot> get exercises => exerciseSlots;

  /// Creates a copy with the given fields replaced.
  WorkoutTemplateVersion copyWith({
    int? versionNumber,
    DateTime? publishedAt,
    List<WorkoutBlock>? blocks,
    List<ChildWorkoutRef>? childWorkouts,
  }) {
    return WorkoutTemplateVersion(
      versionNumber: versionNumber ?? this.versionNumber,
      publishedAt: publishedAt ?? this.publishedAt,
      blocks: blocks ?? this.blocks,
      childWorkouts: childWorkouts ?? this.childWorkouts,
    );
  }

  /// Validates version fields.
  void validate() {
    if (versionNumber < 1) {
      throw ArgumentError('versionNumber must be >= 1');
    }
    if (blocks.length > maxWorkoutBlocksPerVersion) {
      throw ArgumentError(
        'A workout version supports at most '
        '$maxWorkoutBlocksPerVersion blocks',
      );
    }
    if (exerciseSlots.length > maxExerciseSlotsPerWorkoutVersion) {
      throw ArgumentError(
        'A workout version supports at most '
        '$maxExerciseSlotsPerWorkoutVersion exercise slots',
      );
    }

    for (final block in blocks) {
      block.validate();
    }

    for (final child in childWorkouts) {
      child.validate();
    }

    final blockIds = blocks.map((block) => block.blockId).toSet();
    if (blockIds.length != blocks.length) {
      throw ArgumentError('Workout block IDs must be unique within a version');
    }
    final blockSorts = blocks.map((block) => block.sortOrder).toSet();
    if (blockSorts.length != blocks.length) {
      throw ArgumentError(
        'Workout block sortOrder values must be unique within a version',
      );
    }
    for (var index = 0; index < blocks.length; index++) {
      if (!blockSorts.contains(index)) {
        throw ArgumentError(
          'Workout block sortOrder values must be contiguous from 0',
        );
      }
    }
    final slotIds = exerciseSlots.map((slot) => slot.slotId).toSet();
    if (slotIds.length != exerciseSlots.length) {
      throw ArgumentError(
        'Exercise slot IDs must be unique within a workout version',
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
