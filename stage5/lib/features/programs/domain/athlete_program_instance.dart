import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/domain/foundation_models.dart';

/// One published program version materialized for one athlete.
///
/// The athlete owns the instance. A trainer may manage only current or future
/// incomplete workouts while their trainer-client relationship remains active.
class AthleteProgramInstance with Auditable {
  AthleteProgramInstance({
    required this.id,
    required this.athleteOwnerId,
    required this.assigningTrainerId,
    required this.sourceProgramId,
    required this.sourceProgramVersion,
    required this.relationshipMode,
    required this.startDate,
    required this.expectedEndDate,
    required this.workoutCount,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.linkedAt,
    this.unlinkedAt,
    this.unlinkReason,
    this.materializationKey,
    this.propagationState = ProgramPropagationState.complete,
    this.propagationTargetVersion,
    this.propagationAttempt = 0,
    this.propagationStartedAt,
    this.propagationCompletedAt,
    this.propagationFailedAt,
    this.propagationError,
    this.deletedAt,
    this.deletedBy,
  });

  final String id;
  final String athleteOwnerId;
  final String assigningTrainerId;
  final String sourceProgramId;
  final int sourceProgramVersion;
  final ProgramRelationshipMode relationshipMode;
  final String startDate;
  final String expectedEndDate;
  final int workoutCount;
  final AthleteProgramInstanceStatus status;
  final DateTime? linkedAt;
  final DateTime? unlinkedAt;
  final String? unlinkReason;

  /// Caller-supplied idempotency key used to safely retry materialization.
  final String? materializationKey;
  final ProgramPropagationState propagationState;
  final int? propagationTargetVersion;
  final int propagationAttempt;
  final DateTime? propagationStartedAt;
  final DateTime? propagationCompletedAt;
  final DateTime? propagationFailedAt;
  final String? propagationError;

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

  bool get isActive => status == AthleteProgramInstanceStatus.active;
  bool get isLinked =>
      relationshipMode == ProgramRelationshipMode.subscribed &&
      unlinkedAt == null;
  bool get isCopied => relationshipMode == ProgramRelationshipMode.copied;

  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (athleteOwnerId.isEmpty) {
      throw ArgumentError('athleteOwnerId cannot be empty');
    }
    if (assigningTrainerId.isEmpty) {
      throw ArgumentError('assigningTrainerId cannot be empty');
    }
    if (sourceProgramId.isEmpty) {
      throw ArgumentError('sourceProgramId cannot be empty');
    }
    if (sourceProgramVersion < 1) {
      throw ArgumentError('sourceProgramVersion must be >= 1');
    }
    _validateDate(startDate, 'startDate');
    _validateDate(expectedEndDate, 'expectedEndDate');
    if (DateTime.parse(expectedEndDate).isBefore(DateTime.parse(startDate))) {
      throw ArgumentError('expectedEndDate must be >= startDate');
    }
    if (workoutCount < 0) {
      throw ArgumentError('workoutCount must be >= 0');
    }
    if (propagationAttempt < 0) {
      throw ArgumentError('propagationAttempt must be >= 0');
    }
    if (propagationTargetVersion != null && propagationTargetVersion! < 1) {
      throw ArgumentError('propagationTargetVersion must be >= 1');
    }
    if (propagationState == ProgramPropagationState.failed &&
        (propagationError == null || propagationError!.trim().isEmpty)) {
      throw ArgumentError('propagationError is required for failed jobs');
    }
    if (relationshipMode == ProgramRelationshipMode.subscribed) {
      if (linkedAt == null) {
        throw ArgumentError('linkedAt is required for subscriptions');
      }
      if (unlinkedAt != null || unlinkReason != null) {
        throw ArgumentError('A subscription cannot already be unlinked');
      }
    } else if ((unlinkedAt == null) != (unlinkReason == null)) {
      throw ArgumentError(
        'unlinkedAt and unlinkReason must either both be set or both be null',
      );
    }
    if (unlinkReason != null && unlinkReason!.trim().isEmpty) {
      throw ArgumentError('unlinkReason cannot be empty');
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

  static void _validateDate(String value, String field) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw ArgumentError('$field must be ISO 8601 date format (YYYY-MM-DD)');
    }
    try {
      final parsed = DateTime.parse(value);
      final normalized = '${parsed.year.toString().padLeft(4, '0')}-'
          '${parsed.month.toString().padLeft(2, '0')}-'
          '${parsed.day.toString().padLeft(2, '0')}';
      if (normalized != value) {
        throw const FormatException();
      }
    } on FormatException {
      throw ArgumentError('$field must be a valid calendar date');
    }
  }
}
