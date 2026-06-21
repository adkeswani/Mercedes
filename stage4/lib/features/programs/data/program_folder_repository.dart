import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage4/features/programs/domain/program.dart';

/// Firestore repository for owner-scoped program folders.
///
/// Targets the top-level `programFolders` collection. Folders are flat
/// (no nesting) and used to organize a trainer's programs. A program
/// references at most one folder via its `folderId` field.
class ProgramFolderRepository {
  ProgramFolderRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('programFolders');

  /// Verifies the caller owns the folder. Throws [StateError] if not.
  Future<void> verifyOwnership(String folderId, String userId) async {
    final doc = await _collection.doc(folderId).get();
    if (!doc.exists) {
      throw StateError('Folder $folderId not found');
    }
    final ownerId = doc.data()?['ownerId'] as String?;
    if (ownerId != userId) {
      throw StateError('User $userId is not the owner of folder $folderId');
    }
  }

  /// Streams the caller's folders, ordered alphabetically by name.
  Stream<List<ProgramFolder>> watchFolders(String userId) {
    return _collection
        .where('ownerId', isEqualTo: userId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Creates a new folder owned by [userId]. Returns the new document ID.
  Future<String> create({
    required String name,
    required String userId,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    final docRef = _collection.doc();
    await docRef.set({
      'ownerId': userId,
      'name': name.trim(),
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Renames a folder. Throws [StateError] if the caller is not the owner.
  Future<void> rename({
    required String folderId,
    required String name,
    required String userId,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('name cannot be empty');
    }
    await verifyOwnership(folderId, userId);
    await _collection.doc(folderId).update({
      'name': name.trim(),
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a folder and clears `folderId` on any programs that
  /// referenced it (those programs become "Uncategorized").
  ///
  /// Throws [StateError] if the caller is not the owner.
  Future<void> delete({
    required String folderId,
    required String userId,
  }) async {
    await verifyOwnership(folderId, userId);

    final members = await _firestore
        .collection('programs')
        .where('ownerId', isEqualTo: userId)
        .where('folderId', isEqualTo: folderId)
        .get();

    final batch = _firestore.batch();
    for (final doc in members.docs) {
      batch.update(doc.reference, {
        'folderId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.delete(_collection.doc(folderId));
    await batch.commit();
  }

  // -- Serialization helpers --

  ProgramFolder _fromMap(Map<String, dynamic> data, String id) {
    return ProgramFolder(
      id: id,
      ownerId: data['ownerId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      createdBy: data['createdBy'] as String? ?? '',
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String? ?? '',
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
