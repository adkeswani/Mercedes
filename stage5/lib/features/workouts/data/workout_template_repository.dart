import 'dart:convert';

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
    List<ExerciseSlot> exerciseSlots,
    String userId,
  ) async {
    final checked = <String>{};
    for (final slot in exerciseSlots) {
      slot.validate();
      final key = '${slot.exerciseId}:${slot.exerciseVersion}';
      if (!checked.add(key)) continue;

      final header = await _firestore
          .collection('exerciseTemplates')
          .doc(slot.exerciseId)
          .get();
      if (!header.exists || header.data() == null) {
        throw StateError('Exercise ${slot.exerciseId} not found');
      }
      final data = header.data()!;
      final ownerId =
          data['ownerId'] as String? ?? data['createdBy'] as String?;
      if (ownerId != userId) {
        throw StateError(
          'User $userId is not the owner of exercise ${slot.exerciseId}',
        );
      }

      final currentVersion = data['currentVersion'] as int?;
      if (currentVersion == null) {
        if (slot.exerciseVersion != 1) {
          throw StateError(
            'Legacy exercise ${slot.exerciseId} only has version 1',
          );
        }
        continue;
      }
      final version = await header.reference
          .collection('exerciseVersions')
          .doc(slot.exerciseVersion.toString())
          .get();
      if (!version.exists) {
        throw StateError(
          'Exercise ${slot.exerciseId} version '
          '${slot.exerciseVersion} not found',
        );
      }
    }
  }

  /// Generates an opaque Firestore-safe ID for a new exercise occurrence.
  String generateExerciseSlotId() => _collection.doc().id;

  /// Generates an opaque Firestore-safe ID for a new workout block.
  String generateWorkoutBlockId() => _collection.doc().id;

  /// Publishes a new immutable version of the workout template.
  ///
  /// The complete manifest and immutable children are first committed as a
  /// private draft. A transaction then seals that snapshot and advances the
  /// template header, so no incomplete version becomes current.
  ///
  /// Throws [StateError] if the caller is not the creator.
  /// Returns the new version number.
  Future<int> publishVersion({
    required String templateId,
    required String userId,
    List<WorkoutBlock>? blocks,
    List<ExerciseSlot>? exercises,
  }) async {
    if (blocks != null && exercises != null) {
      throw ArgumentError('Provide blocks or legacy exercises, not both');
    }
    final typedBlocks = _canonicalBlocks(
      blocks ?? legacyStandardBlocksFromSlots(exercises ?? const []),
    );
    final version = WorkoutTemplateVersion(
      versionNumber: 1,
      publishedAt: DateTime.now(),
      blocks: typedBlocks,
    );
    version.validate();
    await _verifyOwnership(templateId, userId);
    await _verifyExerciseReferences(version.exerciseSlots, userId);
    final headerRef = _collection.doc(templateId);
    final headerSnap = await headerRef.get();
    if (!headerSnap.exists || headerSnap.data() == null) {
      throw StateError('Workout template $templateId not found');
    }
    final currentVersion = (headerSnap.data()!['currentVersion'] as int?) ?? 0;
    final nextVersion = currentVersion + 1;
    final now = DateTime.now();
    final versionRef = headerRef
        .collection('workoutTemplateVersions')
        .doc(nextVersion.toString());
    final blockMaps = <Map<String, dynamic>>[];
    final slotMaps = <Map<String, dynamic>>[];
    var slotOrder = 0;
    for (final block in typedBlocks) {
      blockMaps.add(_blockToMap(block, slotStartOrder: slotOrder));
      for (final slot in block.slots) {
        slotMaps.add(
          _slotToMap(
            slot,
            blockId: block.blockId,
            blockSortOrder: block.sortOrder,
            slotOrder: slotOrder,
          ),
        );
        slotOrder++;
      }
    }

    final draftData = <String, dynamic>{
      'versionNumber': nextVersion,
      'publishedAt': Timestamp.fromDate(now),
      'storageFormat': 'typedWorkoutBlocksV1',
      'publishState': 'draft',
      'ownerId': userId,
      'blockCount': typedBlocks.length,
      'slotCount': version.exerciseSlots.length,
      'blockIds': typedBlocks.map((block) => block.blockId).toList(),
      'slotIds': version.exerciseSlots.map((slot) => slot.slotId).toList(),
      'blocks': blockMaps,
      'slots': slotMaps,
      'childWorkouts': <Map<String, dynamic>>[],
    };
    final existingDraft = await versionRef.get();
    var shouldCreateDraft = !existingDraft.exists;
    if (existingDraft.exists) {
      final data = existingDraft.data()!;
      if (data['ownerId'] != userId ||
          !const ['draft', 'deleting'].contains(data['publishState'])) {
        throw StateError(
          'Workout version $nextVersion is not an owned pending draft',
        );
      }
      final matches = data['publishState'] == 'draft' &&
          jsonEncode(data['blockIds']) == jsonEncode(draftData['blockIds']) &&
          jsonEncode(data['slotIds']) == jsonEncode(draftData['slotIds']) &&
          jsonEncode(data['blocks']) == jsonEncode(draftData['blocks']) &&
          jsonEncode(data['slots']) == jsonEncode(draftData['slots']);
      if (!matches) {
        await _deletePendingDraft(
          headerRef: headerRef,
          versionRef: versionRef,
          userId: userId,
        );
        shouldCreateDraft = true;
      }
    }
    if (shouldCreateDraft) {
      final draftBatch = _firestore.batch();
      draftBatch.set(versionRef, draftData);
      for (var blockIndex = 0; blockIndex < typedBlocks.length; blockIndex++) {
        final block = typedBlocks[blockIndex];
        draftBatch.set(
          versionRef.collection('workoutBlocks').doc(block.blockId),
          blockMaps[blockIndex],
        );
        for (final slot in block.slots) {
          draftBatch.set(
            versionRef.collection('exerciseSlots').doc(slot.slotId),
            slotMaps.firstWhere(
              (candidate) => candidate['slotId'] == slot.slotId,
            ),
          );
        }
      }
      await draftBatch.commit();
    }

    await _firestore.runTransaction((transaction) async {
      final latestHeader = await transaction.get(headerRef);
      final draft = await transaction.get(versionRef);
      if (!latestHeader.exists ||
          latestHeader.data() == null ||
          draft.data()?['publishState'] != 'draft') {
        throw StateError('Workout version draft is no longer publishable');
      }
      final latestOwner = latestHeader.data()!['ownerId'] as String? ??
          latestHeader.data()!['createdBy'] as String?;
      if (latestOwner != userId) {
        throw StateError('User $userId is not the owner of $templateId');
      }
      if ((latestHeader.data()!['currentVersion'] as int? ?? 0) !=
          currentVersion) {
        throw StateError('Workout template was published concurrently');
      }
      transaction.update(versionRef, {'publishState': 'published'});
      transaction.update(headerRef, {
        'currentVersion': nextVersion,
        'ownerId': userId,
        'updatedAt': Timestamp.fromDate(now),
        'updatedBy': userId,
      });
    });
    return nextVersion;
  }

  Future<void> _deletePendingDraft({
    required DocumentReference<Map<String, dynamic>> headerRef,
    required DocumentReference<Map<String, dynamic>> versionRef,
    required String userId,
  }) async {
    final documents = await Future.wait([headerRef.get(), versionRef.get()]);
    final header = documents[0];
    final draft = documents[1];
    final headerData = header.data();
    final draftData = draft.data();
    final ownerId = headerData?['ownerId'] as String? ??
        headerData?['createdBy'] as String?;
    if (!header.exists ||
        !draft.exists ||
        ownerId != userId ||
        draftData?['ownerId'] != userId ||
        !const ['draft', 'deleting'].contains(draftData?['publishState'])) {
      throw StateError('User $userId cannot replace this workout draft');
    }
    if (draftData?['publishState'] == 'draft') {
      await versionRef.update({'publishState': 'deleting'});
    }
    final children = await Future.wait([
      versionRef.collection('workoutBlocks').get(),
      versionRef.collection('exerciseSlots').get(),
    ]);
    final cleanup = _firestore.batch();
    for (final snapshot in children) {
      for (final child in snapshot.docs) {
        cleanup.delete(child.reference);
      }
    }
    await cleanup.commit();
    await versionRef.update({'blocksCleared': true});
    await versionRef.update({'slotsCleared': true});
    await versionRef.delete();
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
    if (doc.data()!['publishState'] == 'draft') return null;
    final blocks = await _blocksForVersion(doc.reference, doc.data()!);
    return _versionFromMap(doc.data()!, blocks: blocks);
  }

  /// Streams all versions of a workout template, ordered by version number.
  Stream<List<WorkoutTemplateVersion>> watchVersions(String templateId) {
    return _collection.doc(templateId).snapshots().asyncMap((header) async {
      final currentVersion = header.data()?['currentVersion'] as int? ?? 0;
      final versions = await Future.wait([
        for (var version = currentVersion; version >= 1; version--)
          getVersion(templateId, version),
      ]);
      return versions.whereType<WorkoutTemplateVersion>().toList();
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

  /// Returns the typed blocks from the latest published version.
  Future<List<WorkoutBlock>> getLatestBlocks(String templateId) async {
    final template = await getById(templateId);
    if (template == null || !template.hasPublishedVersion) return [];
    final version = await getVersion(templateId, template.currentVersion);
    return version?.blocks ?? [];
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
    required List<WorkoutBlock> blocks,
  }) {
    return WorkoutTemplateVersion(
      versionNumber: (data['versionNumber'] as int?) ?? 1,
      publishedAt: _toDateTime(data['publishedAt']),
      blocks: blocks,
    );
  }

  Future<List<WorkoutBlock>> _blocksForVersion(
    DocumentReference<Map<String, dynamic>> versionRef,
    Map<String, dynamic> data,
  ) async {
    if (data['storageFormat'] == 'typedWorkoutBlocksV1') {
      final embeddedBlocks = data['blocks'];
      final embeddedSlots = data['slots'];
      if (embeddedBlocks is List && embeddedSlots is List) {
        final blockMaps = embeddedBlocks.map((raw) {
          if (raw is! Map) {
            throw StateError('Stored workout block must be a map');
          }
          return Map<String, dynamic>.from(raw);
        }).toList();
        final slotsByBlock = <String, List<ExerciseSlot>>{};
        for (final raw in embeddedSlots) {
          if (raw is! Map) {
            throw StateError('Stored workout slot must be a map');
          }
          final slotMap = Map<String, dynamic>.from(raw);
          final blockId = slotMap['blockId'] as String? ?? '';
          slotsByBlock.putIfAbsent(blockId, () => []).add(
                _slotFromMap(
                  slotMap,
                  fallbackSlotId: slotMap['slotId'] as String? ?? '',
                ),
              );
        }
        for (final slots in slotsByBlock.values) {
          slots.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        }
        return blockMaps
            .map(
              (blockMap) => _blockFromMap(
                blockMap,
                slotsByBlock[blockMap['blockId'] as String? ?? ''] ?? const [],
                fallbackBlockId: blockMap['blockId'] as String? ?? '',
              ),
            )
            .toList();
      }
      final blockSnapshot = await versionRef
          .collection('workoutBlocks')
          .orderBy('sortOrder')
          .get();
      final slotSnapshot = await versionRef.collection('exerciseSlots').get();
      final slotsByBlock = <String, List<ExerciseSlot>>{};
      for (final doc in slotSnapshot.docs) {
        final blockId = doc.data()['blockId'] as String? ?? '';
        slotsByBlock.putIfAbsent(blockId, () => []).add(
              _slotFromMap(
                doc.data(),
                fallbackSlotId: doc.data()['slotId'] as String? ?? doc.id,
              ),
            );
      }
      for (final slots in slotsByBlock.values) {
        slots.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      return blockSnapshot.docs
          .map(
            (doc) => _blockFromMap(
              doc.data(),
              slotsByBlock[doc.data()['blockId'] as String? ?? doc.id] ??
                  const [],
              fallbackBlockId: doc.id,
            ),
          )
          .toList();
    }

    final isPrescriptionSubcollection =
        data['storageFormat'] == 'exercisePrescriptionSubcollection';
    final List<Map<String, dynamic>> exerciseMaps;
    if (isPrescriptionSubcollection) {
      final snapshot = await versionRef
          .collection('exercisePrescriptions')
          .orderBy('sortOrder')
          .get();
      exerciseMaps = snapshot.docs.map((doc) => doc.data()).toList();
    } else {
      exerciseMaps = ((data['exercises'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>();
    }
    return [
      for (var index = 0; index < exerciseMaps.length; index++)
        StandardExerciseBlock(
          blockId: legacyWorkoutBlockId(
            isPrescriptionSubcollection
                ? exerciseMaps[index]['sortOrder'] as int? ?? index
                : index,
          ),
          sortOrder: index,
          exercise: _slotFromMap(
            exerciseMaps[index],
            fallbackSlotId: legacyExerciseSlotId(
              isPrescriptionSubcollection
                  ? exerciseMaps[index]['sortOrder'] as int? ?? index
                  : index,
            ),
          ).copyWith(
            sortOrder: 0,
            legacyStorageOrder: isPrescriptionSubcollection
                ? exerciseMaps[index]['sortOrder'] as int? ?? index
                : index,
          ),
        ),
    ];
  }

  ExerciseSlot _slotFromMap(
    Map<String, dynamic> data, {
    required String fallbackSlotId,
  }) {
    final prescription = data['prescription'] as Map<String, dynamic>? ?? data;
    return ExerciseSlot(
      slotId: data['slotId'] as String? ?? fallbackSlotId,
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

  Map<String, dynamic> _slotToMap(
    ExerciseSlot slot, {
    required String blockId,
    required int blockSortOrder,
    required int slotOrder,
  }) {
    return {
      'slotId': slot.slotId,
      'blockId': blockId,
      'blockSortOrder': blockSortOrder,
      'slotOrder': slotOrder,
      'exerciseId': slot.exerciseId,
      'exerciseVersion': slot.exerciseVersion,
      'sortOrder': slot.sortOrder,
      'exerciseName': slot.exerciseName,
      'prescription': {
        'mode': slot.mode.name,
        'sets': slot.sets,
        'reps': slot.reps,
        'durationSeconds': slot.durationSeconds,
        'weight': slot.weight,
        'restSeconds': slot.restSeconds,
        'notes': slot.notes,
      },
    };
  }

  Map<String, dynamic> _blockToMap(
    WorkoutBlock block, {
    required int slotStartOrder,
  }) {
    final map = <String, dynamic>{
      'blockId': block.blockId,
      'type': block.type.name,
      'sortOrder': block.sortOrder,
      'slotIds': block.slots.map((slot) => slot.slotId).toList(),
      'slotStartOrder': slotStartOrder,
      'slotCount': block.slots.length,
      'title': block.title,
      'notes': block.notes,
    };
    switch (block) {
      case StandardExerciseBlock():
        break;
      case TimedIntervalBlock():
        map.addAll({
          'rounds': block.rounds,
          'workSeconds': block.workSeconds,
          'restSeconds': block.restSeconds,
        });
      case CircuitBlock():
        map.addAll({
          'rounds': block.rounds,
          'restBetweenRoundsSeconds': block.restBetweenRoundsSeconds,
        });
      case ClimbingRouteBlock():
        map.addAll({
          'grade': block.grade,
          'color': block.color,
          'targetAttempts': block.targetAttempts,
        });
    }
    return map;
  }

  List<WorkoutBlock> _canonicalBlocks(List<WorkoutBlock> blocks) {
    final sorted = blocks.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [
      for (final block in sorted) _canonicalBlock(block),
    ];
  }

  WorkoutBlock _canonicalBlock(WorkoutBlock block) {
    final slots = block.slots.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return switch (block) {
      StandardExerciseBlock() => StandardExerciseBlock(
          blockId: block.blockId,
          sortOrder: block.sortOrder,
          exercise: slots.single,
          title: block.title,
          notes: block.notes,
        ),
      TimedIntervalBlock() => TimedIntervalBlock(
          blockId: block.blockId,
          sortOrder: block.sortOrder,
          slots: slots,
          rounds: block.rounds,
          workSeconds: block.workSeconds,
          restSeconds: block.restSeconds,
          title: block.title,
          notes: block.notes,
        ),
      CircuitBlock() => CircuitBlock(
          blockId: block.blockId,
          sortOrder: block.sortOrder,
          slots: slots,
          rounds: block.rounds,
          restBetweenRoundsSeconds: block.restBetweenRoundsSeconds,
          title: block.title,
          notes: block.notes,
        ),
      ClimbingRouteBlock() => ClimbingRouteBlock(
          blockId: block.blockId,
          sortOrder: block.sortOrder,
          route: slots.single,
          grade: block.grade,
          color: block.color,
          targetAttempts: block.targetAttempts,
          title: block.title,
          notes: block.notes,
        ),
    };
  }

  WorkoutBlock _blockFromMap(
    Map<String, dynamic> data,
    List<ExerciseSlot> slots, {
    required String fallbackBlockId,
  }) {
    final blockId = data['blockId'] as String? ?? fallbackBlockId;
    final sortOrder = data['sortOrder'] as int? ?? 0;
    final title = data['title'] as String?;
    final notes = data['notes'] as String?;
    switch (data['type']) {
      case 'timedInterval':
        return TimedIntervalBlock(
          blockId: blockId,
          sortOrder: sortOrder,
          slots: slots,
          rounds: data['rounds'] as int? ?? 1,
          workSeconds: data['workSeconds'] as int? ?? 1,
          restSeconds: data['restSeconds'] as int? ?? 0,
          title: title,
          notes: notes,
        );
      case 'circuit':
        return CircuitBlock(
          blockId: blockId,
          sortOrder: sortOrder,
          slots: slots,
          rounds: data['rounds'] as int? ?? 1,
          restBetweenRoundsSeconds:
              data['restBetweenRoundsSeconds'] as int? ?? 0,
          title: title,
          notes: notes,
        );
      case 'climbingRoute':
        if (slots.length != 1) {
          throw StateError(
            'Climbing route block $blockId must contain exactly one slot',
          );
        }
        return ClimbingRouteBlock(
          blockId: blockId,
          sortOrder: sortOrder,
          route: slots.single,
          grade: data['grade'] as String? ?? '',
          color: data['color'] as String? ?? '',
          targetAttempts: data['targetAttempts'] as int?,
          title: title,
          notes: notes,
        );
      case 'standardExercise':
      default:
        if (slots.length != 1) {
          throw StateError(
            'Standard exercise block $blockId must contain exactly one slot',
          );
        }
        return StandardExerciseBlock(
          blockId: blockId,
          sortOrder: sortOrder,
          exercise: slots.single,
          title: title,
          notes: notes,
        );
    }
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
