import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/programs/domain/enrollment.dart';

/// Firestore repository for program enrollment management.
///
/// Targets the `enrollments/{programId_athleteId}` collection.
/// Enrollment document IDs follow the `{programId}_{athleteId}` convention
/// for fast security-rule lookups via `exists()` / `get()`.
class EnrollmentRepository {
  EnrollmentRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('enrollments');

  /// Verifies the caller is the program owner and the program is assignable.
  /// Throws [StateError] if either check fails.
  Future<void> _verifyCanManageRoster(
    String programId,
    String callerUserId,
  ) async {
    final programDoc = await _firestore
        .collection('programs')
        .doc(programId)
        .get();
    if (!programDoc.exists) {
      throw StateError('Program $programId not found');
    }
    final data = programDoc.data()!;
    if (data['ownerId'] != callerUserId) {
      throw StateError(
        'User $callerUserId is not the owner of program $programId',
      );
    }
    if (data['type'] != ProgramType.assignable.name) {
      throw StateError('Program $programId is not assignable');
    }
  }

  /// Generates the deterministic enrollment document ID.
  static String enrollmentId(String programId, String athleteId) =>
      '${programId}_$athleteId';

  /// Enrolls an athlete in a program.
  ///
  /// Creates the enrollment doc with status `active` and `addedAt` timestamp.
  /// If a removed enrollment already exists for this pair, it is overwritten
  /// with a fresh active enrollment (re-enrollment).
  ///
  /// Throws [StateError] if the athlete is already actively enrolled,
  /// or if the caller is not the program owner,
  /// or if the program is not assignable.
  Future<String> enrollAthlete({
    required String programId,
    required String athleteId,
    required String addedBy,
  }) async {
    await _verifyCanManageRoster(programId, addedBy);
    final docId = enrollmentId(programId, athleteId);
    final docRef = _collection.doc(docId);

    return _firestore.runTransaction<String>((txn) async {
      final existing = await txn.get(docRef);

      if (existing.exists) {
        final status = existing.data()?['status'] as String?;
        if (status == EnrollmentStatus.active.name) {
          throw StateError(
            'Athlete $athleteId is already enrolled in program $programId',
          );
        }
        // Re-enrollment: overwrite the removed enrollment
      }

      txn.set(docRef, {
        'programId': programId,
        'athleteId': athleteId,
        'addedAt': FieldValue.serverTimestamp(),
        'addedBy': addedBy,
        'removedAt': null,
        'removedBy': null,
        'status': EnrollmentStatus.active.name,
        'createdBy': addedBy,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': addedBy,
        'deletedAt': null,
        'deletedBy': null,
      });

      return docId;
    });
  }

  /// Removes an athlete from a program by setting removal fields.
  ///
  /// Sets `removedAt`, `removedBy`, and status to `removed`.
  /// Does not hard-delete — the enrollment doc is preserved for audit.
  ///
  /// Throws [StateError] if the caller is not the program owner.
  Future<void> removeAthlete({
    required String programId,
    required String athleteId,
    required String removedBy,
  }) async {
    await _verifyCanManageRoster(programId, removedBy);
    final docId = enrollmentId(programId, athleteId);
    await _collection.doc(docId).update({
      'removedAt': FieldValue.serverTimestamp(),
      'removedBy': removedBy,
      'status': EnrollmentStatus.removed.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': removedBy,
    });
  }

  /// Streams all active enrollments for a program (owner's roster view).
  ///
  /// The [ownerId] parameter is required so the Firestore query includes
  /// `addedBy == ownerId`, which satisfies the security rule allowing
  /// program owners to list enrollments.
  Stream<List<Enrollment>> watchEnrollments(
    String programId, {
    required String ownerId,
  }) {
    return _collection
        .where('programId', isEqualTo: programId)
        .where('addedBy', isEqualTo: ownerId)
        .where('status', isEqualTo: EnrollmentStatus.active.name)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Streams all active enrollments for an athlete (athlete's enrolled programs).
  Stream<List<Enrollment>> watchMyEnrollments(String athleteId) {
    return _collection
        .where('athleteId', isEqualTo: athleteId)
        .where('status', isEqualTo: EnrollmentStatus.active.name)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Streams all active enrollments created by [ownerId] across every
  /// program they own. Used to build the trainer's athlete picker.
  ///
  /// Requires a composite index on (addedBy, status).
  Stream<List<Enrollment>> watchEnrollmentsByOwner(String ownerId) {
    return _collection
        .where('addedBy', isEqualTo: ownerId)
        .where('status', isEqualTo: EnrollmentStatus.active.name)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Checks whether an athlete is actively enrolled in a program.
  Future<bool> isEnrolled(String programId, String athleteId) async {
    final docId = enrollmentId(programId, athleteId);
    final doc = await _collection.doc(docId).get();
    if (!doc.exists || doc.data() == null) return false;
    return doc.data()!['status'] == EnrollmentStatus.active.name;
  }

  /// Returns a single enrollment by program and athlete, or null.
  Future<Enrollment?> getEnrollment(
    String programId,
    String athleteId,
  ) async {
    final docId = enrollmentId(programId, athleteId);
    final doc = await _collection.doc(docId).get();
    if (!doc.exists || doc.data() == null) return null;
    return _fromMap(doc.data()!, doc.id);
  }

  Enrollment _fromMap(Map<String, dynamic> data, String id) {
    return Enrollment(
      id: id,
      programId: data['programId'] as String? ?? '',
      athleteId: data['athleteId'] as String? ?? '',
      addedAt: _toDateTime(data['addedAt']),
      addedBy: data['addedBy'] as String? ?? '',
      removedAt:
          data['removedAt'] != null ? _toDateTime(data['removedAt']) : null,
      removedBy: data['removedBy'] as String?,
      status: _parseStatus(data['status'] as String?),
      createdAt: _toDateTime(data['createdAt']),
      createdBy: data['createdBy'] as String? ?? '',
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String? ?? '',
      deletedAt:
          data['deletedAt'] != null ? _toDateTime(data['deletedAt']) : null,
      deletedBy: data['deletedBy'] as String?,
    );
  }

  static EnrollmentStatus _parseStatus(String? value) {
    if (value == null) return EnrollmentStatus.active;
    return EnrollmentStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EnrollmentStatus.active,
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
