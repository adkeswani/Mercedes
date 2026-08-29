import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/features/library/data/library_serialization.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';

/// Owner-scoped flat folders for exercise, workout, and program libraries.
///
/// The legacy `programFolders` collection name is retained so existing folder
/// IDs and program references remain valid.
class LibraryFolderRepository {
  LibraryFolderRepository({
    required this.itemType,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final LibraryItemType itemType;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('programFolders');

  Future<void> verifyOwnership(String folderId, String userId) {
    return verifyLibraryFolderOwnership(
      firestore: _firestore,
      folderId: folderId,
      itemType: itemType,
      userId: userId,
    );
  }

  Stream<List<LibraryFolder>> watchFolders(String userId) {
    Query<Map<String, dynamic>> query =
        _collection.where('ownerId', isEqualTo: userId);
    if (itemType != LibraryItemType.program) {
      query = query.where('itemType', isEqualTo: itemType.name);
    }
    return query.orderBy('name').snapshots().map(
          (snapshot) => snapshot.docs
              .where(
                (doc) =>
                    libraryItemTypeFromMap(doc.data()['itemType']) == itemType,
              )
              .map((doc) => _fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<String> create({
    required String name,
    required String userId,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    final docRef = _collection.doc();
    await docRef.set({
      'ownerId': userId,
      'itemType': itemType.name,
      'name': trimmedName,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
      'deletedBy': null,
    });
    return docRef.id;
  }

  Future<void> rename({
    required String folderId,
    required String name,
    required String userId,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    await verifyOwnership(folderId, userId);
    await _collection.doc(folderId).update({
      'itemType': itemType.name,
      'name': trimmedName,
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete({
    required String folderId,
    required String userId,
  }) async {
    await verifyOwnership(folderId, userId);
    await _collection.doc(folderId).update({
      'itemType': itemType.name,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': userId,
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final members = await _firestore
        .collection(_templateCollection)
        .where('ownerId', isEqualTo: userId)
        .where('folderId', isEqualTo: folderId)
        .get();

    for (var start = 0; start < members.docs.length; start += 450) {
      final batch = _firestore.batch();
      final end =
          start + 450 < members.docs.length ? start + 450 : members.docs.length;
      for (final doc in members.docs.sublist(start, end)) {
        batch.update(doc.reference, {
          'folderId': null,
          'updatedBy': userId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    await _collection.doc(folderId).delete();
  }

  String get _templateCollection {
    switch (itemType) {
      case LibraryItemType.exercise:
        return 'exerciseTemplates';
      case LibraryItemType.workout:
        return 'workoutTemplates';
      case LibraryItemType.program:
        return 'programs';
    }
  }

  LibraryFolder _fromMap(Map<String, dynamic> data, String id) {
    return LibraryFolder(
      id: id,
      ownerId: data['ownerId'] as String? ?? '',
      itemType: libraryItemTypeFromMap(data['itemType']),
      name: data['name'] as String? ?? '',
      createdAt: dateTimeFromFirestore(data['createdAt']),
      createdBy: data['createdBy'] as String? ?? '',
      updatedAt: dateTimeFromFirestore(data['updatedAt']),
      updatedBy:
          data['updatedBy'] as String? ?? data['createdBy'] as String? ?? '',
      deletedAt: data['deletedAt'] == null
          ? null
          : dateTimeFromFirestore(data['deletedAt']),
      deletedBy: data['deletedBy'] as String?,
    );
  }
}
