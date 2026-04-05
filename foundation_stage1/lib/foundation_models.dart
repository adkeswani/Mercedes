// Audit/versioning fields for main entities
mixin Auditable {
  DateTime get createdAt;
  String get createdBy;
  DateTime get updatedAt;
  String get updatedBy;
  DateTime? get deletedAt;
  String? get deletedBy;
}

// Foundation domain models for roles, ACL, and audit/versioning fields

enum UserRole {
  account,
  programOwner,
  athlete,
  admin,
}

/// System-level admin, not tied to a specific program.
class Admin with Auditable {
  final DateTime createdAt;
  final String createdBy;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String email;
  final String id;
  final DateTime updatedAt;
  final String updatedBy;

  Admin({
    required this.createdAt,
    required this.createdBy,
    this.deletedAt,
    this.deletedBy,
    required this.email,
    required this.id,
    required this.updatedAt,
    required this.updatedBy,
  });

  @override
  DateTime get createdAt => this.createdAt;
  @override
  String get createdBy => this.createdBy;
  @override
  DateTime get updatedAt => this.updatedAt;
  @override
  String get updatedBy => this.updatedBy;
  @override
  DateTime? get deletedAt => this.deletedAt;
  @override
  String? get deletedBy => this.deletedBy;
}

/// Program-scoped roles
class ProgramRole with Auditable {
  final DateTime createdAt;
  final String createdBy;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String programId;
  final UserRole role; // programOwner or athlete
  final DateTime updatedAt;
  final String updatedBy;
  final String userId;

  ProgramRole({
    required this.createdAt,
    required this.createdBy,
    this.deletedAt,
    this.deletedBy,
    required this.programId,
    required this.role,
    required this.updatedAt,
    required this.updatedBy,
    required this.userId,
  });

  @override
  DateTime get createdAt => this.createdAt;
  @override
  String get createdBy => this.createdBy;
  @override
  DateTime get updatedAt => this.updatedAt;
  @override
  String get updatedBy => this.updatedBy;
  @override
  DateTime? get deletedAt => this.deletedAt;
  @override
  String? get deletedBy => this.deletedBy;
}

/// Enrollment lifecycle fields
class ProgramEnrollment with Auditable {
  final DateTime createdAt;
  final String createdBy;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String programId;
  final DateTime updatedAt;
  final String updatedBy;
  final String userId;

  ProgramEnrollment({
    required this.createdAt,
    required this.createdBy,
    this.deletedAt,
    this.deletedBy,
    required this.programId,
    required this.updatedAt,
    required this.updatedBy,
    required this.userId,
  });

  @override
  DateTime get createdAt => this.createdAt;
  @override
  String get createdBy => this.createdBy;
  @override
  DateTime get updatedAt => this.updatedAt;
  @override
  String get updatedBy => this.updatedBy;
  @override
  DateTime? get deletedAt => this.deletedAt;
  @override
  String? get deletedBy => this.deletedBy;
}

/// Example: ExerciseTemplate with versioning and audit
class ExerciseTemplate with Auditable {
  final DateTime createdAt;
  final String createdBy;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String id;
  final String name;
  final int version;
  final DateTime updatedAt;
  final String updatedBy;

  ExerciseTemplate({
    required this.createdAt,
    required this.createdBy,
    this.deletedAt,
    this.deletedBy,
    required this.id,
    required this.name,
    required this.version,
    required this.updatedAt,
    required this.updatedBy,
  });

  @override
  DateTime get createdAt => this.createdAt;
  @override
  String get createdBy => this.createdBy;
  @override
  DateTime get updatedAt => this.updatedAt;
  @override
  String get updatedBy => this.updatedBy;
  @override
  DateTime? get deletedAt => this.deletedAt;
  @override
  String? get deletedBy => this.deletedBy;
}
