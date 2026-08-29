import 'package:stage5/features/auth/domain/foundation_models.dart';

/// Broad execution category for an exercise.
enum ExerciseType { strength, climbing, conditioning, mobility, skill, other }

/// Measurement captured while performing an exercise.
enum ExerciseMeasurementType {
  repetitions,
  duration,
  distance,
  weight,
  completion,
}

/// Grading systems currently supported by exercise versions.
enum ExerciseGradingSystem { vScale, gymColor }

/// Versioned measurement behavior for an exercise.
class ExerciseMeasurementConfiguration {
  const ExerciseMeasurementConfiguration({
    required this.primary,
    this.secondary = const [],
  });

  final ExerciseMeasurementType primary;
  final List<ExerciseMeasurementType> secondary;

  void validate() {
    if (secondary.contains(primary)) {
      throw ArgumentError('secondary measurements cannot contain primary');
    }
    if (secondary.toSet().length != secondary.length) {
      throw ArgumentError('secondary measurements must be unique');
    }
  }
}

/// Optional versioned grading behavior for an exercise.
class ExerciseGradingConfiguration {
  const ExerciseGradingConfiguration({
    required this.system,
    this.gymColors = const [],
  });

  final ExerciseGradingSystem system;
  final List<String> gymColors;

  void validate() {
    if (system == ExerciseGradingSystem.gymColor &&
        (gymColors.isEmpty || gymColors.any((color) => color.trim().isEmpty))) {
      throw ArgumentError('gymColor grading requires non-empty colors');
    }
    if (system != ExerciseGradingSystem.gymColor && gymColors.isNotEmpty) {
      throw ArgumentError('gymColors are only valid for gymColor grading');
    }
  }
}

/// Immutable execution-relevant exercise content.
class ExerciseVersion {
  ExerciseVersion({
    required this.versionNumber,
    required this.name,
    required this.description,
    required this.instructions,
    required this.exerciseType,
    required this.measurementConfiguration,
    required this.publishedAt,
    required this.publishedBy,
    this.videoUrl,
    this.mediaUrls = const [],
    this.gradingConfiguration,
  });

  final int versionNumber;
  final String name;
  final String description;
  final String instructions;
  final String? videoUrl;
  final List<String> mediaUrls;
  final ExerciseType exerciseType;
  final ExerciseMeasurementConfiguration measurementConfiguration;
  final ExerciseGradingConfiguration? gradingConfiguration;
  final DateTime publishedAt;
  final String publishedBy;

  void validate() {
    if (versionNumber < 1) {
      throw ArgumentError('versionNumber must be >= 1');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError('description cannot be empty');
    }
    if (instructions.trim().isEmpty) {
      throw ArgumentError('instructions cannot be empty');
    }
    if (publishedBy.isEmpty) {
      throw ArgumentError('publishedBy cannot be empty');
    }
    if (mediaUrls.any((url) => url.trim().isEmpty)) {
      throw ArgumentError('mediaUrls cannot contain empty values');
    }
    measurementConfiguration.validate();
    gradingConfiguration?.validate();
  }
}

/// Stable logical exercise header with its currently resolved version.
///
/// Organizational metadata and athlete notes use [id], while execution
/// content lives in immutable [ExerciseVersion] sub-documents.
class ExerciseTemplate with Auditable {
  ExerciseTemplate({
    required this.id,
    required this.ownerId,
    required this.currentVersion,
    required this.version,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.deletedAt,
    this.deletedBy,
  });

  final String id;
  final String ownerId;
  final int currentVersion;
  final ExerciseVersion version;

  String get name => version.name;
  String get description => version.description;
  String get instructions => version.instructions;
  String? get videoUrl => version.videoUrl;
  List<String> get mediaUrls => version.mediaUrls;
  ExerciseType get exerciseType => version.exerciseType;
  ExerciseMeasurementConfiguration get measurementConfiguration =>
      version.measurementConfiguration;
  ExerciseGradingConfiguration? get gradingConfiguration =>
      version.gradingConfiguration;

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

  bool get isDeleted => deletedAt != null;

  ExerciseTemplate copyWith({
    String? id,
    String? ownerId,
    int? currentVersion,
    ExerciseVersion? version,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return ExerciseTemplate(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      currentVersion: currentVersion ?? this.currentVersion,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
    );
  }

  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (ownerId.isEmpty) {
      throw ArgumentError('ownerId cannot be empty');
    }
    if (currentVersion < 1) {
      throw ArgumentError('currentVersion must be >= 1');
    }
    if (version.versionNumber > currentVersion) {
      throw ArgumentError('resolved version cannot exceed currentVersion');
    }
    if (createdBy.isEmpty) {
      throw ArgumentError('createdBy cannot be empty');
    }
    if (updatedBy.isEmpty) {
      throw ArgumentError('updatedBy cannot be empty');
    }
    version.validate();
    Auditable.validateTimestamps(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
