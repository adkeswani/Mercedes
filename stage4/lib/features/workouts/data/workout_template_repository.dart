import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/workouts/domain/workout_template.dart';

/// Firestore repository for workout template CRUD and version publishing.
///
/// Targets `workoutTemplates/{id}` with sub-collection
/// `workoutTemplateVersions/{versionNumber}`.
class WorkoutTemplateRepository {
  WorkoutTemplateRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('workoutTemplates');

  /// Verifies the caller is the workout creator. Throws [StateError] if not.
  Future<void> _verifyOwnership(String id, String userId) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) {
      throw StateError('Workout template $id not found');
    }
    final createdBy = doc.data()?['createdBy'] as String?;
    if (createdBy != userId) {
      throw StateError('User $userId is not the creator of workout $id');
    }
  }

  /// Streams all non-deleted workout templates created by [userId],
  /// ordered by most recently updated first.
  Stream<List<WorkoutTemplate>> watchAll(String userId) {
    return _collection
        .where('createdBy', isEqualTo: userId)
        .where('deletedAt', isNull: true)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _headerFromMap(doc.data(), doc.id))
            .toList());
  }

  /// Returns the workout template header with [id], or null if not found
  /// or soft-deleted.
  Future<WorkoutTemplate?> getById(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    final template = _headerFromMap(doc.data()!, doc.id);
    return template.isDeleted ? null : template;
  }

  /// Creates a new workout template header. Returns the generated doc ID.
  /// Created with currentVersion=0 (no published versions yet).
  Future<String> create({
    required String name,
    required WorkoutType workoutType,
    required String userId,
  }) async {
    final docRef = _collection.doc();
    await docRef.set({
      'name': name,
      'workoutType': workoutType.name,
      'currentVersion': 0,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
      'deletedAt': null,
      'deletedBy': null,
    });
    return docRef.id;
  }

  /// Updates the workout template header's editable fields.
  ///
  /// Throws [StateError] if the caller is not the creator.
  Future<void> update({
    required String id,
    required String name,
    required WorkoutType workoutType,
    required String userId,
  }) async {
    await _verifyOwnership(id, userId);
    await _collection.doc(id).update({
      'name': name,
      'workoutType': workoutType.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
  }

  /// Soft-deletes the workout template.
  ///
  /// Throws [StateError] if the caller is not the creator.
  Future<void> softDelete(String id, String userId) async {
    await _verifyOwnership(id, userId);
    await _collection.doc(id).update({
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
  }

  /// Publishes a new version of the workout template as a Firestore
  /// transaction.
  ///
  /// Atomically:
  /// 1. Reads the header to get the current version number
  /// 2. Creates the version sub-doc with nextVersion
  /// 3. Increments the header's currentVersion
  ///
  /// Throws [StateError] if the caller is not the creator.
  /// Returns the new version number.
  Future<int> publishVersion({
    required String templateId,
    required List<ExercisePrescription> exercises,
    required String userId,
  }) async {
    await _verifyOwnership(templateId, userId);
    return _firestore.runTransaction<int>((txn) async {
      final headerRef = _collection.doc(templateId);
      final headerSnap = await txn.get(headerRef);

      if (!headerSnap.exists) {
        throw StateError('Workout template $templateId not found');
      }

      final currentVersion =
          (headerSnap.data()!['currentVersion'] as int?) ?? 0;
      final nextVersion = currentVersion + 1;
      final now = DateTime.now();

      final versionRef = headerRef
          .collection('workoutTemplateVersions')
          .doc(nextVersion.toString());

      txn.set(versionRef, {
        'versionNumber': nextVersion,
        'publishedAt': Timestamp.fromDate(now),
        'exercises': exercises.map(_prescriptionToMap).toList(),
        'childWorkouts': <Map<String, dynamic>>[],
      });

      txn.update(headerRef, {
        'currentVersion': nextVersion,
        'updatedAt': Timestamp.fromDate(now),
        'updatedBy': userId,
      });

      return nextVersion;
    });
  }

  /// Returns a specific version of the workout template, or null.
  Future<WorkoutTemplateVersion?> getVersion(
    String templateId,
    int versionNumber,
  ) async {
    final doc = await _collection
        .doc(templateId)
        .collection('workoutTemplateVersions')
        .doc(versionNumber.toString())
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return _versionFromMap(doc.data()!);
  }

  /// Streams all versions of a workout template, ordered by version number.
  Stream<List<WorkoutTemplateVersion>> watchVersions(String templateId) {
    return _collection
        .doc(templateId)
        .collection('workoutTemplateVersions')
        .orderBy('versionNumber', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _versionFromMap(doc.data()))
            .toList());
  }

  /// Creates a duplicate of an existing workout template as a new draft.
  ///
  /// The duplicate inherits the name (with " (Copy)" suffix) and workout
  /// type. It starts with currentVersion=0 — the user must publish to
  /// create the first version.
  ///
  /// Returns the new template's document ID.
  Future<String> duplicateTemplate({
    required String sourceTemplateId,
    required String userId,
  }) async {
    final source = await getById(sourceTemplateId);
    if (source == null) {
      throw StateError('Source template $sourceTemplateId not found');
    }

    final newId = await create(
      name: '${source.name} (Copy)',
      workoutType: source.workoutType,
      userId: userId,
    );

    return newId;
  }

  /// Returns the exercises from the latest published version,
  /// or an empty list if no versions exist.
  ///
  /// Used by the UI to pre-populate the draft when duplicating a template.
  Future<List<ExercisePrescription>> getLatestExercises(
    String templateId,
  ) async {
    final template = await getById(templateId);
    if (template == null || !template.hasPublishedVersion) return [];

    final version = await getVersion(templateId, template.currentVersion);
    return version?.exercises ?? [];
  }

  /// Checks whether a workout template is referenced by any published
  /// program version.
  Future<bool> isWorkoutReferenced(String workoutTemplateId) async {
    final snapshot = await _firestore
        .collection('programs')
        .where('deletedAt', isNull: true)
        .get();

    for (final doc in snapshot.docs) {
      final currentVersion = (doc.data()['currentVersion'] as int?) ?? 0;
      if (currentVersion == 0) continue;

      final versionDoc = await doc.reference
          .collection('programVersions')
          .doc(currentVersion.toString())
          .get();
      if (!versionDoc.exists) continue;

      final entries =
          (versionDoc.data()!['entries'] as List<dynamic>?) ?? [];
      for (final w in entries) {
        if ((w as Map<String, dynamic>)['workoutTemplateId'] ==
            workoutTemplateId) {
          return true;
        }
      }
    }
    return false;
  }

  // -- Serialization helpers --

  WorkoutTemplate _headerFromMap(Map<String, dynamic> data, String id) {
    return WorkoutTemplate(
      id: id,
      name: data['name'] as String? ?? '',
      workoutType: _parseWorkoutType(data['workoutType'] as String?),
      currentVersion: (data['currentVersion'] as int?) ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String? ?? '',
      deletedAt:
          data['deletedAt'] != null ? _toDateTime(data['deletedAt']) : null,
      deletedBy: data['deletedBy'] as String?,
    );
  }

  WorkoutTemplateVersion _versionFromMap(Map<String, dynamic> data) {
    final exerciseList = (data['exercises'] as List<dynamic>?) ?? [];
    return WorkoutTemplateVersion(
      versionNumber: (data['versionNumber'] as int?) ?? 1,
      publishedAt: _toDateTime(data['publishedAt']),
      exercises: exerciseList
          .map((e) =>
              _prescriptionFromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  ExercisePrescription _prescriptionFromMap(Map<String, dynamic> data) {
    final prescription =
        data['prescription'] as Map<String, dynamic>? ?? data;
    return ExercisePrescription(
      exerciseId: data['exerciseId'] as String? ?? '',
      sortOrder: (data['sortOrder'] as int?) ?? 0,
      exerciseName: data['exerciseName'] as String?,
      mode: _parseExerciseMode(prescription['mode'] as String?),
      sets: prescription['sets'] as int?,
      reps: prescription['reps'] as String?,
      durationSeconds: prescription['durationSeconds'] as int?,
      weight: prescription['weight'] as String?,
      restSeconds: prescription['restSeconds'] as int?,
      notes: prescription['notes'] as String?,
    );
  }

  Map<String, dynamic> _prescriptionToMap(ExercisePrescription p) {
    return {
      'exerciseId': p.exerciseId,
      'sortOrder': p.sortOrder,
      'exerciseName': p.exerciseName,
      'prescription': {
        'mode': p.mode.name,
        'sets': p.sets,
        'reps': p.reps,
        'durationSeconds': p.durationSeconds,
        'weight': p.weight,
        'restSeconds': p.restSeconds,
        'notes': p.notes,
      },
    };
  }

  static WorkoutType _parseWorkoutType(String? value) {
    if (value == null) return WorkoutType.fullBody;
    return WorkoutType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WorkoutType.fullBody,
    );
  }

  static ExerciseMode _parseExerciseMode(String? value) {
    if (value == null) return ExerciseMode.reps;
    return ExerciseMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ExerciseMode.reps,
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
