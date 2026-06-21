import 'package:stage4/features/auth/domain/foundation_models.dart';

/// Unified comment model supporting three scopes: program-level,
/// workout-level, and exercise-level.
///
/// The scope is determined by which optional ID fields are populated:
/// - programId only → program-level comment (DM replacement)
/// - workoutInstanceId set, exerciseId null → workout-level
/// - workoutInstanceId and exerciseId set → exercise-level
class Comment with Auditable {

  Comment({
    required this.id,
    required this.programId,
    required this.athleteId, required this.authorId, required this.body, required this.createdAt, required this.createdBy, required this.updatedAt, required this.updatedBy, this.workoutInstanceId,
    this.exerciseId,
    this.groupId,
    this.mediaLinks,
    this.deletedAt,
    this.deletedBy,
  });
  final String id;
  final String programId;
  final String? workoutInstanceId;
  final String? exerciseId;
  final String? groupId;
  final String athleteId;
  final String authorId;
  final String body;
  final List<String>? mediaLinks;
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

  /// Whether this is a program-level comment (no workout or exercise scope).
  bool get isProgramLevel =>
      workoutInstanceId == null && exerciseId == null;

  /// Whether this is a workout-level comment.
  bool get isWorkoutLevel =>
      workoutInstanceId != null && exerciseId == null;

  /// Whether this is an exercise-level comment.
  bool get isExerciseLevel =>
      workoutInstanceId != null && exerciseId != null;

  /// Whether this comment is visible to a group (post-MVP).
  bool get isGroupVisible => groupId != null;

  /// Whether this comment has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Validates all required fields, scope constraints, and audit ordering.
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
    if (authorId.isEmpty) {
      throw ArgumentError('authorId cannot be empty');
    }
    if (body.isEmpty) {
      throw ArgumentError('body cannot be empty');
    }
    if (createdBy.isEmpty) {
      throw ArgumentError('createdBy cannot be empty');
    }
    if (updatedBy.isEmpty) {
      throw ArgumentError('updatedBy cannot be empty');
    }

    // Exercise-level requires workout-level scope
    if (exerciseId != null && workoutInstanceId == null) {
      throw ArgumentError(
        'exerciseId requires workoutInstanceId to be set',
      );
    }

    Auditable.validateTimestamps(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

/// Direct message thread between an athlete and a program owner.
///
/// Separate from the unified comments collection because DMs serve
/// a different purpose (open-ended conversation vs. contextual
/// feedback) and have different access patterns.
class DirectMessageThread with Auditable {

  DirectMessageThread({
    required this.id,
    required this.programId,
    required this.athleteId,
    required this.ownerId,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.deletedAt,
    this.deletedBy,
  });
  final String id;
  final String programId;
  final String athleteId;
  final String ownerId;
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

  /// Whether this thread has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Validates all required fields and audit ordering.
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
    if (ownerId.isEmpty) {
      throw ArgumentError('ownerId cannot be empty');
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

/// A single message within a direct message thread.
class Message with Auditable {

  Message({
    required this.id,
    required this.senderId,
    required this.body,
    required this.createdAt, required this.createdBy, required this.updatedAt, required this.updatedBy, this.mediaLinks,
    this.deletedAt,
    this.deletedBy,
  });
  final String id;
  final String senderId;
  final String body;
  final List<String>? mediaLinks;
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

  /// Whether this message has been edited (updatedAt differs from createdAt).
  bool get isEdited => updatedAt.isAfter(createdAt);

  /// Whether this message has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Validates all required fields and audit ordering.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (senderId.isEmpty) {
      throw ArgumentError('senderId cannot be empty');
    }
    if (body.isEmpty) {
      throw ArgumentError('body cannot be empty');
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
