import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage3/features/exercises/domain/exercise_note.dart';

/// Firestore repository for per-athlete exercise notes.
///
/// Notes are stored at `users/{userId}/exerciseNotes/{exerciseTemplateId}`.
/// Each athlete has their own private subcollection — no cross-user access.
class ExerciseNoteRepository {
  ExerciseNoteRepository({
    required this.userId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String userId;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('users').doc(userId).collection('exerciseNotes');

  /// Saves a note for an exercise template.
  ///
  /// Creates or overwrites the note doc. Uses exerciseTemplateId as the
  /// document ID for 1:1 mapping.
  Future<void> saveNote({
    required String exerciseTemplateId,
    required String exerciseName,
    required String note,
  }) async {
    await _collection.doc(exerciseTemplateId).set({
      'exerciseTemplateId': exerciseTemplateId,
      'exerciseName': exerciseName,
      'note': note,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a note for an exercise template (hard delete).
  Future<void> deleteNote(String exerciseTemplateId) async {
    await _collection.doc(exerciseTemplateId).delete();
  }

  /// Returns a single note by exercise template ID, or null.
  Future<ExerciseNote?> getNote(String exerciseTemplateId) async {
    final doc = await _collection.doc(exerciseTemplateId).get();
    if (!doc.exists || doc.data() == null) return null;
    return _fromMap(doc.data()!, doc.id);
  }

  /// Streams all notes for this user.
  ///
  /// Returns a map of exerciseTemplateId → ExerciseNote for efficient
  /// lookup when rendering exercise lists.
  Stream<Map<String, ExerciseNote>> watchNotes() {
    return _collection.snapshots().map((snapshot) {
      final map = <String, ExerciseNote>{};
      for (final doc in snapshot.docs) {
        final note = _fromMap(doc.data(), doc.id);
        map[note.exerciseTemplateId] = note;
      }
      return map;
    });
  }

  ExerciseNote _fromMap(Map<String, dynamic> data, String id) {
    return ExerciseNote(
      id: id,
      exerciseTemplateId: data['exerciseTemplateId'] as String? ?? id,
      exerciseName: data['exerciseName'] as String? ?? '',
      note: data['note'] as String? ?? '',
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
