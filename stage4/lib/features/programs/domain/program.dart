import 'package:stage4/core/enums.dart';
import 'package:stage4/features/auth/domain/foundation_models.dart';
import 'package:stage4/features/load/domain/load_model.dart';

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
    this.folderId,
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

  /// Optional folder grouping for owner organization.
  ///
  /// When null, the program is treated as "Uncategorized". Folders are
  /// flat (no nesting) and owner-scoped — see [ProgramFolder].
  final String? folderId;

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

  /// Whether this is a personal (self-only) program.
  bool get isPersonal => type == ProgramType.personal;

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
    String? folderId,
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
      folderId: folderId ?? this.folderId,
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
/// schedule of workouts. A program is a reusable *relative* schedule:
/// each entry carries a [ProgramScheduleEntry.dayOffset] measured in days
/// from the program's start (day 0). When a program is assigned to an
/// athlete with a concrete start date, entries materialize into workout
/// instances at `startDate + dayOffset`.
///
/// Enrollments and workout instances reference the (programId,
/// programVersion) pair to preserve history.
class ProgramVersion {
  ProgramVersion({
    required this.versionNumber,
    required this.publishedAt,
    required this.entries,
    this.changeNote,
  });
  final int versionNumber;
  final DateTime publishedAt;
  final List<ProgramScheduleEntry> entries;
  final String? changeNote;

  /// The program length in days, derived from the largest [dayOffset].
  ///
  /// Day 0 counts as a one-day program, so this is `maxDayOffset + 1`.
  /// Returns 0 for an empty schedule.
  int get durationDays {
    if (entries.isEmpty) return 0;
    return entries.map((e) => e.dayOffset).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// Validates version fields.
  void validate() {
    if (versionNumber < 1) {
      throw ArgumentError('versionNumber must be >= 1');
    }

    for (final entry in entries) {
      entry.validate();
    }

    // Validate sort order uniqueness
    final sorts = entries.map((e) => e.sortOrder).toSet();
    if (sorts.length != entries.length) {
      throw ArgumentError(
        'Schedule entry sortOrder values must be unique within a program version',
      );
    }
  }
}

/// A single scheduled workout within a program version.
///
/// A program is a reusable relative schedule, so each entry is anchored to
/// a [dayOffset] (days from the program start, day 0). The same workout may
/// appear at multiple offsets — repeats are allowed and expected (e.g. a
/// recurrence generator may fill many days with the same workout).
///
/// [workoutName] is denormalized at publish time for historical stability —
/// even if the workout template is later renamed or deleted, published
/// versions retain the name as it was when published.
class ProgramScheduleEntry {
  ProgramScheduleEntry({
    required this.workoutTemplateId,
    required this.workoutTemplateVersion,
    required this.dayOffset,
    required this.sortOrder,
    this.workoutName,
  });
  final String workoutTemplateId;
  final int workoutTemplateVersion;

  /// Days from the program start (day 0). Must be >= 0.
  final int dayOffset;

  /// Stable ordering key, unique within a program version.
  final int sortOrder;
  final String? workoutName;

  /// Creates a copy with the given fields replaced.
  ProgramScheduleEntry copyWith({
    String? workoutTemplateId,
    int? workoutTemplateVersion,
    int? dayOffset,
    int? sortOrder,
    String? workoutName,
  }) {
    return ProgramScheduleEntry(
      workoutTemplateId: workoutTemplateId ?? this.workoutTemplateId,
      workoutTemplateVersion:
          workoutTemplateVersion ?? this.workoutTemplateVersion,
      dayOffset: dayOffset ?? this.dayOffset,
      sortOrder: sortOrder ?? this.sortOrder,
      workoutName: workoutName ?? this.workoutName,
    );
  }

  /// Validates entry fields.
  void validate() {
    if (workoutTemplateId.isEmpty) {
      throw ArgumentError('workoutTemplateId cannot be empty');
    }
    if (workoutTemplateVersion < 1) {
      throw ArgumentError('workoutTemplateVersion must be >= 1');
    }
    if (dayOffset < 0) {
      throw ArgumentError('dayOffset must be >= 0');
    }
    if (sortOrder < 0) {
      throw ArgumentError('sortOrder must be >= 0');
    }
  }
}

/// A flat, owner-scoped folder for organizing programs.
///
/// Folders have no nesting. A program references at most one folder via
/// [Program.folderId]; a null reference means "Uncategorized".
class ProgramFolder {
  ProgramFolder({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String id;
  final String ownerId;
  final String name;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;

  /// Creates a copy with the given fields replaced.
  ProgramFolder copyWith({
    String? id,
    String? ownerId,
    String? name,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return ProgramFolder(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  /// Validates folder fields.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (ownerId.isEmpty) {
      throw ArgumentError('ownerId cannot be empty');
    }
    if (name.isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    if (createdBy.isEmpty) {
      throw ArgumentError('createdBy cannot be empty');
    }
    if (updatedBy.isEmpty) {
      throw ArgumentError('updatedBy cannot be empty');
    }
  }
}
