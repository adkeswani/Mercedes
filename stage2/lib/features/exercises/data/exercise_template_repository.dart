import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage2/features/exercises/domain/exercise_template.dart';

/// Firestore repository for exercise template CRUD.
///
/// Targets the `exerciseTemplates/{exerciseId}` collection.
/// Uses server timestamps for audit fields and supports soft-delete.
class ExerciseTemplateRepository {
  ExerciseTemplateRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('exerciseTemplates');

  /// Streams all non-deleted exercise templates created by [userId],
  /// ordered by most recently updated first.
  Stream<List<ExerciseTemplate>> watchAll(String userId) {
    return _collection
        .where('createdBy', isEqualTo: userId)
        .where('deletedAt', isNull: true)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Returns the exercise template with [id], or null if not found
  /// or soft-deleted.
  Future<ExerciseTemplate?> getById(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    final template = _fromMap(doc.data()!, doc.id);
    return template.isDeleted ? null : template;
  }

  /// Creates a new exercise template. Returns the generated document ID.
  ///
  /// Preallocates the Firestore doc ID so the domain entity has a real
  /// ID before the write occurs.
  Future<String> create({
    required String name,
    required String description,
    required String instructions,
    required String userId,
    String? videoUrl,
  }) async {
    final docRef = _collection.doc();
    await docRef.set({
      'name': name,
      'description': description,
      'instructions': instructions,
      'videoUrl': videoUrl,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
      'deletedAt': null,
      'deletedBy': null,
    });
    return docRef.id;
  }

  /// Updates an existing exercise template's editable fields.
  Future<void> update({
    required String id,
    required String name,
    required String description,
    required String instructions,
    required String userId,
    String? videoUrl,
  }) async {
    await _collection.doc(id).update({
      'name': name,
      'description': description,
      'instructions': instructions,
      'videoUrl': videoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
  }

  /// Soft-deletes the exercise template by setting deletedAt/deletedBy.
  Future<void> softDelete(String id, String userId) async {
    await _collection.doc(id).update({
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
  }

  ExerciseTemplate _fromMap(Map<String, dynamic> data, String id) {
    return ExerciseTemplate(
      id: id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      instructions: data['instructions'] as String? ?? '',
      videoUrl: data['videoUrl'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String? ?? '',
      deletedAt: data['deletedAt'] != null
          ? _toDateTime(data['deletedAt'])
          : null,
      deletedBy: data['deletedBy'] as String?,
    );
  }

  /// Converts a Firestore value (Timestamp or null) to DateTime.
  /// Falls back to epoch for pending server timestamps.
  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
