import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage3/core/enums.dart';
import 'package:stage3/features/programs/domain/program.dart';

/// Firestore repository for program CRUD and version publishing.
///
/// Targets `programs/{programId}` with sub-collection
/// `programVersions/{versionNumber}`.
class ProgramRepository {
  ProgramRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('programs');

  /// Streams all non-deleted programs owned by [userId],
  /// ordered by most recently updated first.
  Stream<List<Program>> watchAll(String userId) {
    return _collection
        .where('ownerId', isEqualTo: userId)
        .where('deletedAt', isNull: true)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _headerFromMap(doc.data(), doc.id))
            .toList());
  }

  /// Returns the program with [id], or null if not found or soft-deleted.
  Future<Program?> getById(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    final program = _headerFromMap(doc.data()!, doc.id);
    return program.isDeleted ? null : program;
  }

  /// Creates a new program. Returns the generated document ID.
  Future<String> create({
    required String name,
    required ProgramType type,
    required String userId,
    String? description,
  }) async {
    final docRef = _collection.doc();
    await docRef.set({
      'name': name,
      'description': description,
      'ownerId': userId,
      'type': type.name,
      'status': ProgramStatus.draft.name,
      'currentVersion': 0,
      'typeWeightOverrides': null,
      'loadStrategyId': null,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
      'deletedBy': null,
    });
    return docRef.id;
  }

  /// Updates an existing program's editable fields.
  Future<void> update({
    required String id,
    required String name,
    required String userId,
    String? description,
  }) async {
    await _collection.doc(id).update({
      'name': name,
      'description': description,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Soft-deletes the program.
  Future<void> softDelete(String id, String userId) async {
    await _collection.doc(id).update({
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Publishes a new version of the program as a Firestore transaction.
  ///
  /// Atomically:
  /// 1. Reads the header to get the current version number
  /// 2. Creates the version sub-doc with nextVersion
  /// 3. Increments the header's currentVersion and sets status to published
  ///
  /// Returns the new version number.
  Future<int> publishVersion({
    required String programId,
    required List<ProgramWorkoutRef> workouts,
    required String userId,
    String? changeNote,
  }) async {
    return _firestore.runTransaction<int>((txn) async {
      final headerRef = _collection.doc(programId);
      final headerSnap = await txn.get(headerRef);

      if (!headerSnap.exists) {
        throw StateError('Program $programId not found');
      }

      final currentVersion =
          (headerSnap.data()!['currentVersion'] as int?) ?? 0;
      final nextVersion = currentVersion + 1;
      final now = DateTime.now();

      final versionRef = headerRef
          .collection('programVersions')
          .doc(nextVersion.toString());

      txn.set(versionRef, {
        'versionNumber': nextVersion,
        'publishedAt': Timestamp.fromDate(now),
        'workouts': workouts.map(_workoutRefToMap).toList(),
        'changeNote': changeNote,
      });

      txn.update(headerRef, {
        'currentVersion': nextVersion,
        'status': ProgramStatus.published.name,
        'updatedAt': Timestamp.fromDate(now),
      });

      return nextVersion;
    });
  }

  /// Returns a specific version of the program, or null.
  Future<ProgramVersion?> getVersion(
    String programId,
    int versionNumber,
  ) async {
    final doc = await _collection
        .doc(programId)
        .collection('programVersions')
        .doc(versionNumber.toString())
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return _versionFromMap(doc.data()!);
  }

  /// Streams all versions of a program, ordered by version number.
  Stream<List<ProgramVersion>> watchVersions(String programId) {
    return _collection
        .doc(programId)
        .collection('programVersions')
        .orderBy('versionNumber', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _versionFromMap(doc.data()))
            .toList());
  }

  /// Creates a copy of an existing program as a new draft.
  ///
  /// The copy inherits the name (with " (Copy)" suffix), description, type,
  /// and workout references from the latest published version. The copy
  /// starts as a draft with currentVersion=0 — the user must publish to
  /// create the first version.
  ///
  /// Returns the new program's document ID.
  Future<String> copyProgram({
    required String sourceProgramId,
    required String userId,
  }) async {
    final source = await getById(sourceProgramId);
    if (source == null) {
      throw StateError('Source program $sourceProgramId not found');
    }

    // Create the new program header as a draft
    final newId = await create(
      name: '${source.name} (Copy)',
      type: source.type,
      userId: userId,
      description: source.description,
    );

    // If the source has published versions, copy the latest version's
    // workout list into the draft's local state. The user will see these
    // when they open the builder and can edit before publishing.
    // We don't auto-publish — the copy starts as a draft.

    return newId;
  }

  /// Returns the workout refs from the latest published version,
  /// or an empty list if no versions exist.
  ///
  /// Used by the UI to pre-populate the draft when copying a program.
  Future<List<ProgramWorkoutRef>> getLatestWorkoutRefs(
    String programId,
  ) async {
    final program = await getById(programId);
    if (program == null || program.currentVersion == 0) return [];

    final version = await getVersion(programId, program.currentVersion);
    return version?.workouts ?? [];
  }

  // -- Serialization helpers --

  Program _headerFromMap(Map<String, dynamic> data, String id) {
    return Program(
      id: id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String?,
      ownerId: data['ownerId'] as String? ?? '',
      type: _parseProgramType(data['type'] as String?),
      status: _parseProgramStatus(data['status'] as String?),
      currentVersion: (data['currentVersion'] as int?) ?? 0,
      typeWeightOverrides: _parseTypeWeightOverrides(
        data['typeWeightOverrides'] as Map<String, dynamic>?,
      ),
      loadStrategyId: data['loadStrategyId'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: data['createdBy'] as String? ?? '',
      deletedAt:
          data['deletedAt'] != null ? _toDateTime(data['deletedAt']) : null,
      deletedBy: data['deletedBy'] as String?,
    );
  }

  ProgramVersion _versionFromMap(Map<String, dynamic> data) {
    final workoutList = (data['workouts'] as List<dynamic>?) ?? [];
    return ProgramVersion(
      versionNumber: (data['versionNumber'] as int?) ?? 1,
      publishedAt: _toDateTime(data['publishedAt']),
      workouts: workoutList
          .map((w) => _workoutRefFromMap(w as Map<String, dynamic>))
          .toList(),
      changeNote: data['changeNote'] as String?,
    );
  }

  ProgramWorkoutRef _workoutRefFromMap(Map<String, dynamic> data) {
    return ProgramWorkoutRef(
      workoutTemplateId: data['workoutTemplateId'] as String? ?? '',
      workoutTemplateVersion: (data['workoutTemplateVersion'] as int?) ?? 1,
      sortOrder: (data['sortOrder'] as int?) ?? 0,
      workoutName: data['workoutName'] as String?,
    );
  }

  Map<String, dynamic> _workoutRefToMap(ProgramWorkoutRef ref) {
    return {
      'workoutTemplateId': ref.workoutTemplateId,
      'workoutTemplateVersion': ref.workoutTemplateVersion,
      'sortOrder': ref.sortOrder,
      'workoutName': ref.workoutName,
    };
  }

  static ProgramType _parseProgramType(String? value) {
    if (value == null) return ProgramType.assignable;
    return ProgramType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ProgramType.assignable,
    );
  }

  static ProgramStatus _parseProgramStatus(String? value) {
    if (value == null) return ProgramStatus.draft;
    return ProgramStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ProgramStatus.draft,
    );
  }

  static Map<WorkoutType, int>? _parseTypeWeightOverrides(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final result = <WorkoutType, int>{};
    for (final entry in data.entries) {
      final type = WorkoutType.values.firstWhere(
        (e) => e.name == entry.key,
        orElse: () => WorkoutType.fullBody,
      );
      result[type] = (entry.value as num).toInt();
    }
    return result.isEmpty ? null : result;
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
