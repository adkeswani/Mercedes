import 'package:stage5/features/auth/domain/foundation_models.dart';

const maxLibraryTags = 20;
const maxLibraryTagLength = 40;

/// Template kind used to scope shared organizational abstractions.
enum LibraryItemType { exercise, workout, program }

/// Immutable source identity recorded when a logical template is copied.
class TemplateProvenance {
  const TemplateProvenance({
    required this.sourceTemplateId,
    required this.sourceOwnerId,
    required this.sourceVersion,
    required this.copiedAt,
    required this.copiedBy,
  });

  final String sourceTemplateId;
  final String sourceOwnerId;
  final int sourceVersion;
  final DateTime copiedAt;
  final String copiedBy;

  void validate() {
    if (sourceTemplateId.isEmpty) {
      throw ArgumentError('sourceTemplateId cannot be empty');
    }
    if (sourceOwnerId.isEmpty) {
      throw ArgumentError('sourceOwnerId cannot be empty');
    }
    if (sourceVersion < 0) {
      throw ArgumentError('sourceVersion must be >= 0');
    }
    if (copiedBy.isEmpty) {
      throw ArgumentError('copiedBy cannot be empty');
    }
  }
}

class LibrarySourceReference {
  const LibrarySourceReference({
    required this.templateId,
    required this.version,
  });

  final String templateId;
  final int? version;
}

LibrarySourceReference resolveLibraryEditorSource({
  required String targetTemplateId,
  required int targetVersion,
  required String? routeSourceTemplateId,
  required TemplateProvenance? provenance,
}) {
  if (targetVersion > 0) {
    return LibrarySourceReference(
      templateId: targetTemplateId,
      version: targetVersion,
    );
  }
  if (provenance != null) {
    return LibrarySourceReference(
      templateId: provenance.sourceTemplateId,
      version: provenance.sourceVersion,
    );
  }
  return LibrarySourceReference(
    templateId: routeSourceTemplateId ?? targetTemplateId,
    version: routeSourceTemplateId == null ? targetVersion : null,
  );
}

/// Shared stable metadata for logical exercise, workout, and program headers.
abstract interface class LibraryItem {
  List<String> get tags;
  String? get folderId;
  TemplateProvenance? get provenance;
}

/// Returns trimmed, case-insensitively unique tags while preserving display case.
List<String> normalizeLibraryTags(Iterable<String> tags) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final value in tags) {
    final tag = value.trim();
    if (tag.isEmpty) {
      throw ArgumentError('tags cannot contain empty values');
    }
    if (tag.length > maxLibraryTagLength) {
      throw ArgumentError(
        'tags cannot exceed $maxLibraryTagLength characters',
      );
    }
    if (seen.add(tag.toLowerCase())) {
      normalized.add(tag);
    }
  }
  if (normalized.length > maxLibraryTags) {
    throw ArgumentError('templates support at most $maxLibraryTags tags');
  }
  return List.unmodifiable(normalized);
}

void validateLibraryMetadata({
  required List<String> tags,
  required String? folderId,
  required TemplateProvenance? provenance,
}) {
  final normalized = normalizeLibraryTags(tags);
  if (normalized.length != tags.length) {
    throw ArgumentError('tags must be case-insensitively unique');
  }
  for (var i = 0; i < tags.length; i++) {
    if (normalized[i] != tags[i]) {
      throw ArgumentError('tags must be trimmed');
    }
  }
  if (folderId != null && folderId.isEmpty) {
    throw ArgumentError('folderId cannot be empty');
  }
  provenance?.validate();
}

/// Flat owner-scoped folder shared by template library implementations.
class LibraryFolder with Auditable {
  LibraryFolder({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.itemType = LibraryItemType.program,
    this.deletedAt,
    this.deletedBy,
  });

  final String id;
  final String ownerId;
  final String name;
  final LibraryItemType itemType;
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

  LibraryFolder copyWith({
    String? id,
    String? ownerId,
    String? name,
    LibraryItemType? itemType,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return LibraryFolder(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      itemType: itemType ?? this.itemType,
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
    if (name.trim().isEmpty) {
      throw ArgumentError('name cannot be empty');
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
