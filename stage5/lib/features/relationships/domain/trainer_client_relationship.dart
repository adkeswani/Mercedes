import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/domain/foundation_models.dart';

/// Durable authorization boundary between a trainer and an athlete.
class TrainerClientRelationship with Auditable {
  TrainerClientRelationship({
    required this.id,
    required this.trainerId,
    required this.athleteId,
    required this.status,
    required this.startedAt,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.endedAt,
    this.deletedAt,
    this.deletedBy,
  });

  final String id;
  final String trainerId;
  final String athleteId;
  final TrainerClientRelationshipStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
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

  bool get isActive => status == TrainerClientRelationshipStatus.active;
  bool get isEnded => status == TrainerClientRelationshipStatus.ended;
  bool get isDeleted => deletedAt != null;

  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (trainerId.isEmpty) {
      throw ArgumentError('trainerId cannot be empty');
    }
    if (athleteId.isEmpty) {
      throw ArgumentError('athleteId cannot be empty');
    }
    if (trainerId == athleteId) {
      throw ArgumentError('trainerId and athleteId must be different');
    }
    if (createdBy.isEmpty) {
      throw ArgumentError('createdBy cannot be empty');
    }
    if (updatedBy.isEmpty) {
      throw ArgumentError('updatedBy cannot be empty');
    }
    if (isActive && endedAt != null) {
      throw ArgumentError('endedAt must be null while status is active');
    }
    if (isEnded && endedAt == null) {
      throw ArgumentError('endedAt is required when status is ended');
    }
    if (endedAt != null && startedAt.isAfter(endedAt!)) {
      throw ArgumentError('startedAt must be <= endedAt');
    }
    Auditable.validateTimestamps(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
