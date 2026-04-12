// Audit/versioning fields for main entities
mixin Auditable {
  DateTime get createdAt;
  String get createdBy;
  DateTime get updatedAt;
  String get updatedBy;
  DateTime? get deletedAt;
  String? get deletedBy;

  /// Utility to validate audit timestamps ordering.
  static void validateTimestamps({
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) {
    if (createdAt.isAfter(updatedAt)) {
      throw ArgumentError('createdAt must be <= updatedAt');
    }
    if (deletedAt != null) {
      if (createdAt.isAfter(deletedAt)) {
        throw ArgumentError('createdAt must be <= deletedAt');
      }
      if (updatedAt.isAfter(deletedAt)) {
        throw ArgumentError('updatedAt must be <= deletedAt');
      }
    }
  }
}

// Foundation domain models for roles, ACL, and audit/versioning fields

enum UserRole { account, programOwner, athlete, admin }

/// System-level admin, not tied to a specific program.
class Admin with Auditable {

  Admin({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.deletedAt,
    this.deletedBy,
  });
  final String id;
  final String email;
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

  // Utility: Check if admin is deleted
  bool get isDeleted => deletedAt != null;

  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('Admin id cannot be empty');
    }
    if (email.isEmpty) {
      throw ArgumentError('Admin email cannot be empty');
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

/// Program-scoped roles
class ProgramRole with Auditable {

  ProgramRole({
    required this.userId,
    required this.programId,
    required this.role,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.deletedAt,
    this.deletedBy,
  });
  final String userId;
  final String programId;
  final UserRole role; // programOwner or athlete
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

  // Utility: Check if role is deleted
  bool get isDeleted => deletedAt != null;

  void validate() {
    if (userId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }
    if (programId.isEmpty) {
      throw ArgumentError('programId cannot be empty');
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

/// Enrollment lifecycle fields
class ProgramEnrollment with Auditable {

  ProgramEnrollment({
    required this.userId,
    required this.programId,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.deletedAt,
    this.deletedBy,
  });
  final String userId;
  final String programId;
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

  // Utility: Check if enrollment is deleted
  bool get isDeleted => deletedAt != null;

  void validate() {
    if (userId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }
    if (programId.isEmpty) {
      throw ArgumentError('programId cannot be empty');
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

/// Reusable exercise definition with video and instructions.
///
/// Exercise templates are not versioned — they are standalone definitions
/// referenced by workout template versions via exerciseId.
class ExerciseTemplate with Auditable {

  ExerciseTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions, required this.createdAt, required this.createdBy, required this.updatedAt, required this.updatedBy, this.videoUrl,
    this.deletedAt,
    this.deletedBy,
  });
  final String id;
  final String name;
  final String description;
  final String? videoUrl;
  final String instructions;
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

  /// Validates all required fields and audit timestamp ordering.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (name.isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    if (description.isEmpty) {
      throw ArgumentError('description cannot be empty');
    }
    if (instructions.isEmpty) {
      throw ArgumentError('instructions cannot be empty');
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
