import 'package:stage4/features/auth/domain/foundation_models.dart';

/// Reusable exercise definition with video and instructions.
///
/// Exercise templates are not versioned — they are standalone definitions
/// referenced by workout template versions via exerciseId.
class ExerciseTemplate with Auditable {
  ExerciseTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.videoUrl,
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

  /// Creates a copy with the given fields replaced.
  ExerciseTemplate copyWith({
    String? id,
    String? name,
    String? description,
    String? instructions,
    String? videoUrl,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return ExerciseTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      instructions: instructions ?? this.instructions,
      videoUrl: videoUrl ?? this.videoUrl,
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
