import 'package:foundation_stage1/enums.dart';
import 'package:foundation_stage1/foundation_models.dart';

/// Athlete enrollment in a program with lifecycle timestamps.
///
/// Enrollment is a manual access grant with explicit `addedAt`/`removedAt`
/// timestamps for audit. The status field provides fast ACL lookups via
/// a composite index on (programId, athleteId, status).
class Enrollment with Auditable {

  Enrollment({
    required this.id,
    required this.programId,
    required this.athleteId,
    required this.addedAt,
    required this.addedBy,
    required this.status, required this.createdAt, required this.createdBy, required this.updatedAt, required this.updatedBy, this.removedAt,
    this.removedBy,
    this.deletedAt,
    this.deletedBy,
  });
  final String id;
  final String programId;
  final String athleteId;
  final DateTime addedAt;
  final String addedBy;
  final DateTime? removedAt;
  final String? removedBy;
  final EnrollmentStatus status;
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

  /// Whether the athlete is currently active in this program.
  bool get isActive => status == EnrollmentStatus.active;

  /// Whether the athlete has been removed from this program.
  bool get isRemoved => status == EnrollmentStatus.removed;

  /// Whether this enrollment has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Validates all required fields, lifecycle constraints, and audit ordering.
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
    if (addedBy.isEmpty) {
      throw ArgumentError('addedBy cannot be empty');
    }
    if (createdBy.isEmpty) {
      throw ArgumentError('createdBy cannot be empty');
    }
    if (updatedBy.isEmpty) {
      throw ArgumentError('updatedBy cannot be empty');
    }

    if (status == EnrollmentStatus.removed) {
      if (removedAt == null) {
        throw ArgumentError(
          'removedAt is required when status is removed',
        );
      }
      if (removedBy == null || removedBy!.isEmpty) {
        throw ArgumentError(
          'removedBy is required when status is removed',
        );
      }
      if (addedAt.isAfter(removedAt!)) {
        throw ArgumentError('addedAt must be <= removedAt');
      }
    }

    Auditable.validateTimestamps(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
