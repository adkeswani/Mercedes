import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/library/data/library_serialization.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

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

  /// Verifies the caller owns the workout. Legacy documents derive ownership
  /// from `createdBy` until they are mutated and backfilled with `ownerId`.
  Future<void> _verifyOwnership(String id, String userId) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) {
      throw StateError('Workout template $id not found');
    }
    final data = doc.data()!;
    final ownerId = data['ownerId'] as String? ?? data['createdBy'] as String?;
    if (ownerId != userId) {
      throw StateError('User $userId is not the owner of workout $id');
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
    List<String> tags = const [],
    String? folderId,
    TemplateProvenance? provenance,
  }) async {
    final normalizedTags = normalizeLibraryTags(tags);
    await _validateCreationMetadata(
      userId: userId,
      folderId: folderId,
      provenance: provenance,
    );
    final docRef = _collection.doc();
    await docRef.set({
      'name': name,
      'workoutType': workoutType.name,
      'currentVersion': 0,
      'ownerId': userId,
      'tags': normalizedTags,
      'folderId': folderId,
      'provenance': provenanceToMap(
        provenance,
        copiedAt: FieldValue.serverTimestamp(),
      ),
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
      'deletedAt': null,
      'deletedBy': null,
    });
    return docRef.id;
  }

  /// Updates stable owner organization without publishing a workout version.
  Future<void> updateOrganization({
    required String id,
    required List<String> tags,
    required String? folderId,
    required String userId,
  }) async {
    await _verifyOwnership(id, userId);
    final normalizedTags = normalizeLibraryTags(tags);
    if (folderId != null) {
      await verifyLibraryFolderOwnership(
        firestore: _firestore,
        folderId: folderId,
        itemType: LibraryItemType.workout,
        userId: userId,
      );
    }
    await _collection.doc(id).update({
      'ownerId': userId,
      'tags': normalizedTags,
      'folderId': folderId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
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
      'ownerId': userId,
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
      'ownerId': userId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
  }

  Future<void> _verifyExerciseReferences(
    List<ExercisePrescription> exercises,
    String userId,
  ) async {
    final checked = <String>{};
    for (final exercise in exercises) {
      exercise.validate();
      final key = '${exercise.exerciseId}:${exercise.exerciseVersion}';
      if (!checked.add(key)) continue;

      final header = await _firestore
          .collection('exerciseTemplates')
          .doc(exercise.exerciseId)
          .get();
      if (!header.exists || header.data() == null) {
        throw StateError('Exercise ${exercise.exerciseId} not found');
      }
      final data = header.data()!;
      final ownerId =
          data['ownerId'] as String? ?? data['createdBy'] as String?;
      if (ownerId != userId) {
        throw StateError(
          'User $userId is not the owner of exercise ${exercise.exerciseId}',
        );
      }

      final currentVersion = data['currentVersion'] as int?;
      if (currentVersion == null) {
        if (exercise.exerciseVersion != 1) {
          throw StateError(
            'Legacy exercise ${exercise.exerciseId} only has version 1',
          );
        }
        continue;
      }
      final version = await header.reference
          .collection('exerciseVersions')
          .doc(exercise.exerciseVersion.toString())
          .get();
      if (!version.exists) {
        throw StateError(
          'Exercise ${exercise.exerciseId} version '
          '${exercise.exerciseVersion} not found',
        );
      }
    }
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
    WorkoutTemplateVersion(
      versionNumber: 1,
      publishedAt: DateTime.now(),
      exercises: exercises,
    ).validate();
    await _verifyOwnership(templateId, userId);
    await _verifyExerciseReferences(exercises, userId);
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
        'storageFormat': 'exercisePrescriptionSubcollection',
        'prescriptionCount': exercises.length,
        'childWorkouts': <Map<String, dynamic>>[],
      });
      for (final exercise in exercises) {
        txn.set(
          versionRef
              .collection('exercisePrescriptions')
              .doc(exercise.sortOrder.toString()),
          _prescriptionToMap(exercise),
        );
      }

      txn.update(headerRef, {
        'currentVersion': nextVersion,
        'ownerId': userId,
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
    final exercises = await _exerciseMapsForVersion(doc.reference, doc.data()!);
    return _versionFromMap(doc.data()!, exerciseMaps: exercises);
  }

  /// Streams all versions of a workout template, ordered by version number.
  Stream<List<WorkoutTemplateVersion>> watchVersions(String templateId) {
    return _collection
        .doc(templateId)
        .collection('workoutTemplateVersions')
        .orderBy('versionNumber', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      return Future.wait(snapshot.docs.map((doc) async {
        final exercises =
            await _exerciseMapsForVersion(doc.reference, doc.data());
        return _versionFromMap(doc.data(), exerciseMaps: exercises);
      }));
    });
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
      tags: source.tags,
      folderId: source.ownerId == userId ? source.folderId : null,
      provenance: TemplateProvenance(
        sourceTemplateId: source.id,
        sourceOwnerId: source.ownerId,
        sourceVersion: source.currentVersion,
        copiedAt: DateTime.now(),
        copiedBy: userId,
      ),
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

      final entries = (versionDoc.data()!['entries'] as List<dynamic>?) ?? [];
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
      ownerId: data['ownerId'] as String? ?? data['createdBy'] as String? ?? '',
      name: data['name'] as String? ?? '',
      workoutType: _parseWorkoutType(data['workoutType'] as String?),
      currentVersion: (data['currentVersion'] as int?) ?? 0,
      tags: libraryTagsFromMap(data['tags']),
      folderId: data['folderId'] as String?,
      provenance: provenanceFromMap(data['provenance']),
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String? ?? '',
      deletedAt:
          data['deletedAt'] != null ? _toDateTime(data['deletedAt']) : null,
      deletedBy: data['deletedBy'] as String?,
    );
  }

  WorkoutTemplateVersion _versionFromMap(
    Map<String, dynamic> data, {
    List<Map<String, dynamic>>? exerciseMaps,
  }) {
    final exerciseList =
        exerciseMaps ?? (data['exercises'] as List<dynamic>?) ?? [];
    return WorkoutTemplateVersion(
      versionNumber: (data['versionNumber'] as int?) ?? 1,
      publishedAt: _toDateTime(data['publishedAt']),
      exercises: exerciseList
          .map((e) => _prescriptionFromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _exerciseMapsForVersion(
    DocumentReference<Map<String, dynamic>> versionRef,
    Map<String, dynamic> data,
  ) async {
    if (data['storageFormat'] != 'exercisePrescriptionSubcollection') {
      return ((data['exercises'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>();
    }
    final snapshot = await versionRef
        .collection('exercisePrescriptions')
        .orderBy('sortOrder')
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  ExercisePrescription _prescriptionFromMap(Map<String, dynamic> data) {
    final prescription = data['prescription'] as Map<String, dynamic>? ?? data;
    return ExercisePrescription(
      exerciseId: data['exerciseId'] as String? ?? '',
      exerciseVersion: data['exerciseVersion'] as int? ?? 1,
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
      'exerciseVersion': p.exerciseVersion,
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

  Future<void> _validateCreationMetadata({
    required String userId,
    required String? folderId,
    required TemplateProvenance? provenance,
  }) async {
    if (userId.isEmpty) throw ArgumentError('userId cannot be empty');
    provenance?.validate();
    if (provenance != null && provenance.copiedBy != userId) {
      throw StateError('Copy provenance must identify its owner as copiedBy');
    }
    if (folderId != null) {
      await verifyLibraryFolderOwnership(
        firestore: _firestore,
        folderId: folderId,
        itemType: LibraryItemType.workout,
        userId: userId,
      );
    }
  }
}
