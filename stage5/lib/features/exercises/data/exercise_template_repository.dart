import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/library/data/library_serialization.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';

enum ExerciseBackfillResult { backfilled, notNeeded }

/// Firestore repository for logical exercises and immutable versions.
class ExerciseTemplateRepository {
  ExerciseTemplateRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('exerciseTemplates');

  String _ownerOf(Map<String, dynamic> data) =>
      data['ownerId'] as String? ?? data['createdBy'] as String? ?? '';

  void _verifyOwnershipData(
    String id,
    Map<String, dynamic> data,
    String userId,
  ) {
    if (_ownerOf(data) != userId) {
      throw StateError('User $userId is not the owner of exercise $id');
    }
  }

  Future<void> _verifyOwnership(String id, String userId) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) {
      throw StateError('Exercise template $id not found');
    }
    _verifyOwnershipData(id, doc.data()!, userId);
  }

  Stream<List<ExerciseTemplate>> watchAll(String userId) {
    return _collection
        .where('createdBy', isEqualTo: userId)
        .where('deletedAt', isNull: true)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final templates = await Future.wait(
        snapshot.docs.map(
          (doc) => _resolveTemplate(doc, includeDeleted: false),
        ),
      );
      return templates.whereType<ExerciseTemplate>().toList();
    });
  }

  Future<ExerciseTemplate?> getById(String id, {int? versionNumber}) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return _resolveTemplate(
      doc,
      includeDeleted: false,
      versionNumber: versionNumber,
    );
  }

  Future<ExerciseTemplate?> getByIdIncludingDeleted(
    String id, {
    int? versionNumber,
  }) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return _resolveTemplate(
      doc,
      includeDeleted: true,
      versionNumber: versionNumber,
    );
  }

  Future<ExerciseVersion?> getVersion(String id, int versionNumber) async {
    final header = await _collection.doc(id).get();
    if (!header.exists || header.data() == null) return null;
    return _resolveVersion(header.reference, header.data()!, versionNumber);
  }

  Stream<List<ExerciseVersion>> watchVersions(String id) {
    return _collection
        .doc(id)
        .collection('exerciseVersions')
        .orderBy('versionNumber', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => _versionFromMap(doc.data())).toList(),
        );
  }

  /// Creates the logical header and immutable version 1 atomically.
  Future<String> create({
    required String name,
    required String description,
    required String instructions,
    required String userId,
    String? videoUrl,
    List<String> mediaUrls = const [],
    ExerciseType exerciseType = ExerciseType.other,
    ExerciseMeasurementConfiguration measurementConfiguration =
        const ExerciseMeasurementConfiguration(
      primary: ExerciseMeasurementType.repetitions,
    ),
    ExerciseGradingConfiguration? gradingConfiguration,
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
    final version = ExerciseVersion(
      versionNumber: 1,
      name: name,
      description: description,
      instructions: instructions,
      videoUrl: videoUrl,
      mediaUrls: mediaUrls,
      exerciseType: exerciseType,
      measurementConfiguration: measurementConfiguration,
      gradingConfiguration: gradingConfiguration,
      publishedAt: DateTime.now(),
      publishedBy: userId,
    );
    version.validate();

    final batch = _firestore.batch();
    batch.set(docRef, {
      'ownerId': userId,
      'currentVersion': 1,
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
    batch.set(
      docRef.collection('exerciseVersions').doc('1'),
      _versionToMap(version, publishedAt: FieldValue.serverTimestamp()),
    );
    await batch.commit();
    return docRef.id;
  }

  /// Creates a new logical exercise with version 1 copied from [sourceId].
  Future<String> copyExercise({
    required String sourceId,
    required String userId,
  }) async {
    final source = await getById(sourceId);
    if (source == null) {
      throw StateError('Source exercise $sourceId not found');
    }
    final now = DateTime.now();
    return create(
      name: '${source.name} (Copy)',
      description: source.description,
      instructions: source.instructions,
      userId: userId,
      videoUrl: source.videoUrl,
      mediaUrls: source.mediaUrls,
      exerciseType: source.exerciseType,
      measurementConfiguration: source.measurementConfiguration,
      gradingConfiguration: source.gradingConfiguration,
      tags: source.tags,
      folderId: source.ownerId == userId ? source.folderId : null,
      provenance: TemplateProvenance(
        sourceTemplateId: source.id,
        sourceOwnerId: source.ownerId,
        sourceVersion: source.version.versionNumber,
        copiedAt: now,
        copiedBy: userId,
      ),
    );
  }

  /// Updates stable owner organization without publishing a content version.
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
        itemType: LibraryItemType.exercise,
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

  /// Publishes changed execution content as the next immutable version.
  Future<int> update({
    required String id,
    required String name,
    required String description,
    required String instructions,
    required String userId,
    String? videoUrl,
    List<String>? mediaUrls,
    ExerciseType? exerciseType,
    ExerciseMeasurementConfiguration? measurementConfiguration,
    ExerciseGradingConfiguration? gradingConfiguration,
  }) {
    return publishVersion(
      id: id,
      name: name,
      description: description,
      instructions: instructions,
      userId: userId,
      videoUrl: videoUrl,
      mediaUrls: mediaUrls,
      exerciseType: exerciseType,
      measurementConfiguration: measurementConfiguration,
      gradingConfiguration: gradingConfiguration,
    );
  }

  /// Publishes changed execution content as the next immutable version.
  Future<int> publishVersion({
    required String id,
    required String name,
    required String description,
    required String instructions,
    required String userId,
    String? videoUrl,
    List<String>? mediaUrls,
    ExerciseType? exerciseType,
    ExerciseMeasurementConfiguration? measurementConfiguration,
    ExerciseGradingConfiguration? gradingConfiguration,
  }) async {
    await _verifyOwnership(id, userId);
    return _firestore.runTransaction<int>((transaction) async {
      final headerRef = _collection.doc(id);
      final header = await transaction.get(headerRef);
      if (!header.exists || header.data() == null) {
        throw StateError('Exercise template $id not found');
      }
      final data = header.data()!;
      _verifyOwnershipData(id, data, userId);
      final legacy = !_hasVersionedHeader(data);
      final currentVersion = legacy ? 1 : data['currentVersion'] as int;
      final current = await _resolveVersionForTransaction(
        transaction,
        headerRef,
        data,
        currentVersion,
      );
      final nextVersion = currentVersion + 1;
      final next = ExerciseVersion(
        versionNumber: nextVersion,
        name: name,
        description: description,
        instructions: instructions,
        videoUrl: videoUrl,
        mediaUrls: mediaUrls ?? current.mediaUrls,
        exerciseType: exerciseType ?? current.exerciseType,
        measurementConfiguration:
            measurementConfiguration ?? current.measurementConfiguration,
        gradingConfiguration:
            gradingConfiguration ?? current.gradingConfiguration,
        publishedAt: DateTime.now(),
        publishedBy: userId,
      );
      next.validate();

      if (legacy) {
        transaction.set(
          headerRef.collection('exerciseVersions').doc('1'),
          _versionToMap(current),
        );
      }
      transaction.set(
        headerRef.collection('exerciseVersions').doc(nextVersion.toString()),
        _versionToMap(next),
      );
      transaction.update(
        headerRef,
        _versionedHeaderUpdate(
          ownerId: userId,
          currentVersion: nextVersion,
          updatedBy: userId,
        ),
      );
      return nextVersion;
    });
  }

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

  /// Materializes a legacy exercise document as immutable version 1.
  Future<ExerciseBackfillResult> backfillLegacyVersion(
    String id,
    String userId,
  ) async {
    await _verifyOwnership(id, userId);
    return _firestore.runTransaction<ExerciseBackfillResult>((
      transaction,
    ) async {
      final headerRef = _collection.doc(id);
      final header = await transaction.get(headerRef);
      if (!header.exists || header.data() == null) {
        throw StateError('Exercise template $id not found');
      }
      final data = header.data()!;
      _verifyOwnershipData(id, data, userId);
      if (_hasVersionedHeader(data)) {
        return ExerciseBackfillResult.notNeeded;
      }

      final version = _legacyVersion(data);
      transaction.set(
        headerRef.collection('exerciseVersions').doc('1'),
        _versionToMap(version),
      );
      transaction.update(
        headerRef,
        _versionedHeaderUpdate(
          ownerId: userId,
          currentVersion: 1,
          updatedBy: userId,
        ),
      );
      return ExerciseBackfillResult.backfilled;
    });
  }

  /// Backfills every legacy exercise owned by [userId].
  Future<int> backfillOwnedLegacyExercises(String userId) async {
    final snapshot =
        await _collection.where('createdBy', isEqualTo: userId).get();
    var count = 0;
    for (final doc in snapshot.docs) {
      final result = await backfillLegacyVersion(doc.id, userId);
      if (result == ExerciseBackfillResult.backfilled) count++;
    }
    return count;
  }

  Future<bool> isExerciseReferenced(String exerciseId) async {
    final snapshot = await _firestore
        .collection('workoutTemplates')
        .where('deletedAt', isNull: true)
        .get();

    for (final doc in snapshot.docs) {
      final currentVersion = (doc.data()['currentVersion'] as int?) ?? 0;
      if (currentVersion == 0) continue;
      final versionDoc = await doc.reference
          .collection('workoutTemplateVersions')
          .doc(currentVersion.toString())
          .get();
      if (!versionDoc.exists) continue;
      final exercises =
          (versionDoc.data()!['exercises'] as List<dynamic>?) ?? [];
      if (exercises.any(
        (exercise) =>
            (exercise as Map<String, dynamic>)['exerciseId'] == exerciseId,
      )) {
        return true;
      }
      if (versionDoc.data()!['storageFormat'] ==
          'exercisePrescriptionSubcollection') {
        final prescriptions = await versionDoc.reference
            .collection('exercisePrescriptions')
            .where('exerciseId', isEqualTo: exerciseId)
            .limit(1)
            .get();
        if (prescriptions.docs.isNotEmpty) return true;
      }
    }
    return false;
  }

  Future<ExerciseTemplate?> _resolveTemplate(
    DocumentSnapshot<Map<String, dynamic>> header, {
    required bool includeDeleted,
    int? versionNumber,
  }) async {
    final data = header.data()!;
    if (!includeDeleted && data['deletedAt'] != null) return null;
    final currentVersion =
        _hasVersionedHeader(data) ? data['currentVersion'] as int : 1;
    final resolvedVersion = versionNumber ?? currentVersion;
    final version = await _resolveVersion(
      header.reference,
      data,
      resolvedVersion,
    );
    if (version == null) return null;
    return ExerciseTemplate(
      id: header.id,
      ownerId: _ownerOf(data),
      currentVersion: currentVersion,
      version: version,
      tags: libraryTagsFromMap(data['tags']),
      folderId: data['folderId'] as String?,
      provenance: provenanceFromMap(data['provenance']),
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy:
          data['updatedBy'] as String? ?? data['createdBy'] as String? ?? '',
      deletedAt:
          data['deletedAt'] != null ? _toDateTime(data['deletedAt']) : null,
      deletedBy: data['deletedBy'] as String?,
    );
  }

  Future<ExerciseVersion?> _resolveVersion(
    DocumentReference<Map<String, dynamic>> headerRef,
    Map<String, dynamic> header,
    int versionNumber,
  ) async {
    final version = await headerRef
        .collection('exerciseVersions')
        .doc('$versionNumber')
        .get();
    if (version.exists && version.data() != null) {
      return _versionFromMap(version.data()!);
    }
    if (versionNumber == 1 && !_hasVersionedHeader(header)) {
      return _legacyVersion(header);
    }
    return null;
  }

  Future<ExerciseVersion> _resolveVersionForTransaction(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> headerRef,
    Map<String, dynamic> header,
    int versionNumber,
  ) async {
    if (!_hasVersionedHeader(header)) return _legacyVersion(header);
    final version = await transaction.get(
      headerRef.collection('exerciseVersions').doc('$versionNumber'),
    );
    if (!version.exists || version.data() == null) {
      throw StateError(
        'Exercise ${headerRef.id} version $versionNumber not found',
      );
    }
    return _versionFromMap(version.data()!);
  }

  bool _hasVersionedHeader(Map<String, dynamic> data) =>
      data['currentVersion'] is int && (data['currentVersion'] as int) >= 1;

  ExerciseVersion _legacyVersion(Map<String, dynamic> data) {
    return ExerciseVersion(
      versionNumber: 1,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      instructions: data['instructions'] as String? ?? '',
      videoUrl: data['videoUrl'] as String?,
      mediaUrls: _stringList(data['mediaUrls']),
      exerciseType: _parseExerciseType(data['exerciseType'] as String?),
      measurementConfiguration: _measurementFromMap(
        data['measurementConfiguration'] as Map<String, dynamic>?,
      ),
      gradingConfiguration: _gradingFromMap(
        data['gradingConfiguration'] as Map<String, dynamic>?,
      ),
      publishedAt: _toDateTime(data['createdAt']),
      publishedBy: data['createdBy'] as String? ?? '',
    );
  }

  ExerciseVersion _versionFromMap(Map<String, dynamic> data) {
    return ExerciseVersion(
      versionNumber: data['versionNumber'] as int? ?? 1,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      instructions: data['instructions'] as String? ?? '',
      videoUrl: data['videoUrl'] as String?,
      mediaUrls: _stringList(data['mediaUrls']),
      exerciseType: _parseExerciseType(data['exerciseType'] as String?),
      measurementConfiguration: _measurementFromMap(
        data['measurementConfiguration'] as Map<String, dynamic>?,
      ),
      gradingConfiguration: _gradingFromMap(
        data['gradingConfiguration'] as Map<String, dynamic>?,
      ),
      publishedAt: _toDateTime(data['publishedAt']),
      publishedBy: data['publishedBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> _versionToMap(
    ExerciseVersion version, {
    Object? publishedAt,
  }) {
    return {
      'versionNumber': version.versionNumber,
      'name': version.name,
      'description': version.description,
      'instructions': version.instructions,
      'videoUrl': version.videoUrl,
      'mediaUrls': version.mediaUrls,
      'exerciseType': version.exerciseType.name,
      'measurementConfiguration': {
        'primary': version.measurementConfiguration.primary.name,
        'secondary': version.measurementConfiguration.secondary
            .map((measurement) => measurement.name)
            .toList(),
      },
      'gradingConfiguration': version.gradingConfiguration == null
          ? null
          : {
              'system': version.gradingConfiguration!.system.name,
              'gymColors': version.gradingConfiguration!.gymColors,
            },
      'publishedAt': publishedAt ?? Timestamp.fromDate(version.publishedAt),
      'publishedBy': version.publishedBy,
    };
  }

  Map<String, dynamic> _versionedHeaderUpdate({
    required String ownerId,
    required int currentVersion,
    required String updatedBy,
  }) {
    return {
      'ownerId': ownerId,
      'currentVersion': currentVersion,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
      'name': FieldValue.delete(),
      'description': FieldValue.delete(),
      'instructions': FieldValue.delete(),
      'videoUrl': FieldValue.delete(),
      'mediaUrls': FieldValue.delete(),
      'exerciseType': FieldValue.delete(),
      'measurementConfiguration': FieldValue.delete(),
      'gradingConfiguration': FieldValue.delete(),
    };
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
        itemType: LibraryItemType.exercise,
        userId: userId,
      );
    }
  }

  static List<String> _stringList(dynamic value) =>
      (value as List<dynamic>?)?.whereType<String>().toList() ?? const [];

  static ExerciseType _parseExerciseType(String? value) {
    return ExerciseType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ExerciseType.other,
    );
  }

  static ExerciseMeasurementConfiguration _measurementFromMap(
    Map<String, dynamic>? data,
  ) {
    final primaryName = data?['primary'] as String?;
    final primary = ExerciseMeasurementType.values.firstWhere(
      (type) => type.name == primaryName,
      orElse: () => ExerciseMeasurementType.repetitions,
    );
    final secondaryNames = _stringList(data?['secondary']);
    return ExerciseMeasurementConfiguration(
      primary: primary,
      secondary: secondaryNames
          .map(
            (name) => ExerciseMeasurementType.values.firstWhere(
              (type) => type.name == name,
              orElse: () => ExerciseMeasurementType.completion,
            ),
          )
          .toList(),
    );
  }

  static ExerciseGradingConfiguration? _gradingFromMap(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final systemName = data['system'] as String?;
    final system = ExerciseGradingSystem.values
        .where((value) => value.name == systemName)
        .firstOrNull;
    if (system == null) return null;
    return ExerciseGradingConfiguration(
      system: system,
      gymColors: _stringList(data['gymColors']),
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
