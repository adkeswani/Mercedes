import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/features/library/domain/library_metadata.dart';

List<String> libraryTagsFromMap(dynamic value) =>
    (value as List<dynamic>?)?.whereType<String>().toList() ?? const [];

TemplateProvenance? provenanceFromMap(dynamic value) {
  if (value is! Map<String, dynamic>) return null;
  return TemplateProvenance(
    sourceTemplateId: value['sourceTemplateId'] as String? ?? '',
    sourceOwnerId: value['sourceOwnerId'] as String? ?? '',
    sourceVersion: value['sourceVersion'] as int? ?? 0,
    copiedAt: dateTimeFromFirestore(value['copiedAt']),
    copiedBy: value['copiedBy'] as String? ?? '',
  );
}

Map<String, dynamic>? provenanceToMap(
  TemplateProvenance? provenance, {
  Object? copiedAt,
}) {
  if (provenance == null) return null;
  return {
    'sourceTemplateId': provenance.sourceTemplateId,
    'sourceOwnerId': provenance.sourceOwnerId,
    'sourceVersion': provenance.sourceVersion,
    'copiedAt': copiedAt ?? Timestamp.fromDate(provenance.copiedAt),
    'copiedBy': provenance.copiedBy,
  };
}

DateTime dateTimeFromFirestore(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return DateTime.fromMillisecondsSinceEpoch(0);
}

LibraryItemType libraryItemTypeFromMap(dynamic value) {
  return LibraryItemType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => LibraryItemType.program,
  );
}

Future<void> verifyLibraryFolderOwnership({
  required FirebaseFirestore firestore,
  required String folderId,
  required LibraryItemType itemType,
  required String userId,
}) async {
  final folder =
      await firestore.collection('programFolders').doc(folderId).get();
  if (!folder.exists || folder.data() == null) {
    throw StateError('Folder $folderId not found');
  }
  final data = folder.data()!;
  final ownerId = data['ownerId'] as String?;
  final actualType = libraryItemTypeFromMap(data['itemType']);
  if (ownerId != userId ||
      actualType != itemType ||
      data['deletedAt'] != null) {
    throw StateError(
      'User $userId does not own a ${itemType.name} folder $folderId',
    );
  }
}

/// Verifies deletion authority and returns whether cleanup is being resumed.
Future<bool> verifyLibraryFolderDeletionOwnership({
  required FirebaseFirestore firestore,
  required String folderId,
  required LibraryItemType itemType,
  required String userId,
}) async {
  final folder =
      await firestore.collection('programFolders').doc(folderId).get();
  if (!folder.exists || folder.data() == null) {
    throw StateError('Folder $folderId not found');
  }
  final data = folder.data()!;
  final ownerId = data['ownerId'] as String?;
  final actualType = libraryItemTypeFromMap(data['itemType']);
  if (ownerId != userId || actualType != itemType) {
    throw StateError(
      'User $userId does not own a ${itemType.name} folder $folderId',
    );
  }
  return data['deletedAt'] != null;
}

Future<void> verifyActiveClientScope({
  required FirebaseFirestore firestore,
  required String trainerId,
  required String clientAthleteId,
}) async {
  if (clientAthleteId.trim().isEmpty || clientAthleteId == trainerId) {
    throw StateError('Client scope must reference an active athlete');
  }
  final relationship = await firestore
      .collection('trainerClientRelationships')
      .doc('${trainerId}_$clientAthleteId')
      .get();
  final data = relationship.data();
  if (!relationship.exists ||
      data == null ||
      data['trainerId'] != trainerId ||
      data['athleteId'] != clientAthleteId ||
      data['status'] != 'active' ||
      data['deletedAt'] != null) {
    throw StateError(
      'User $trainerId has no active relationship with $clientAthleteId',
    );
  }
}
