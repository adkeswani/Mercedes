import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/relationships/data/trainer_client_relationship_repository.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

/// Firestore repository for workout instance management.
///
/// Targets the `workoutInstances/{instanceId}` collection.
/// Handles scheduling, completion, cancellation, and calendar queries.
class WorkoutInstanceRepository {
  WorkoutInstanceRepository({
    FirebaseFirestore? firestore,
    DateTime Function()? now,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _now = now ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('workoutInstances');

  CollectionReference<Map<String, dynamic>> get _programInstances =>
      _firestore.collection('athleteProgramInstances');

  String get _today {
    final now = _now().toUtc();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String get _localToday {
    final now = _now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Duration get _untilNextLocalDay {
    final now = _now();
    final tomorrow = now.isUtc
        ? DateTime.utc(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day + 1);
    final duration = tomorrow.difference(now);
    return duration > Duration.zero ? duration : const Duration(seconds: 1);
  }

  Future<void> _verifyActiveRelationship(
    String trainerId,
    String athleteId,
  ) async {
    if (trainerId == athleteId) return;
    final relationship = await _firestore
        .collection('trainerClientRelationships')
        .doc(
          TrainerClientRelationshipRepository.relationshipId(
            trainerId,
            athleteId,
          ),
        )
        .get();
    if (!relationship.exists ||
        relationship.data()?['status'] !=
            TrainerClientRelationshipStatus.active.name) {
      throw StateError(
        'Trainer $trainerId has no active relationship with $athleteId',
      );
    }
  }

  /// Verifies the caller can assign workouts in this program.
  ///
  /// For assignable programs, the owner may assign to an active enrollee and
  /// an active enrollee may assign to themselves. For personal programs,
  /// caller must be both owner and athlete.
  ///
  /// Returns the verified program owner and the published program version when
  /// this is enrolled-athlete self-assignment.
  Future<({String ownerId, int? selfProgramVersion})> _verifyCanAssign({
    required String programId,
    required String athleteId,
    required String assignedBy,
  }) async {
    final programDoc =
        await _firestore.collection('programs').doc(programId).get();
    if (!programDoc.exists) {
      throw StateError('Program $programId not found');
    }
    final data = programDoc.data()!;
    final ownerId = data['ownerId'] as String?;
    final type = data['type'] as String?;
    final currentVersion = (data['currentVersion'] as int?) ?? 0;
    if (ownerId == null || ownerId.isEmpty) {
      throw StateError('Program $programId has no owner');
    }

    if (type == 'personal') {
      if (ownerId != assignedBy || athleteId != assignedBy) {
        throw StateError('Personal programs only allow self-assignment');
      }
      return (ownerId: ownerId, selfProgramVersion: null);
    }

    await _verifyActiveRelationship(ownerId, athleteId);

    if (ownerId != assignedBy && athleteId != assignedBy) {
      throw StateError(
        'User $assignedBy cannot assign program $programId to $athleteId',
      );
    }

    final enrollmentDoc = await _firestore
        .collection('enrollments')
        .doc('${programId}_$athleteId')
        .get();
    if (!enrollmentDoc.exists || enrollmentDoc.data()?['status'] != 'active') {
      throw StateError(
        'Athlete $athleteId is not actively enrolled in program $programId',
      );
    }

    if (ownerId == assignedBy) {
      return (ownerId: ownerId, selfProgramVersion: null);
    }
    if (currentVersion < 1) {
      throw StateError('Program $programId has no published version');
    }
    return (ownerId: ownerId, selfProgramVersion: currentVersion);
  }

  Future<void> _verifyWorkoutInProgram({
    required String programId,
    required int programVersion,
    required String workoutTemplateId,
    required int workoutTemplateVersion,
  }) async {
    final versionDoc = await _firestore
        .collection('programs')
        .doc(programId)
        .collection('programVersions')
        .doc(programVersion.toString())
        .get();
    final entries =
        (versionDoc.data()?['entries'] as List<dynamic>?) ?? const [];
    final available = entries.any((raw) {
      final entry = raw as Map<String, dynamic>;
      return entry['workoutTemplateId'] == workoutTemplateId &&
          entry['workoutTemplateVersion'] == workoutTemplateVersion;
    });
    if (!available) {
      throw StateError(
        'Workout $workoutTemplateId version $workoutTemplateVersion '
        'is not in program $programId version $programVersion',
      );
    }
  }

  /// Assigns a single workout to an athlete on a specific date.
  ///
  /// Creates a workout instance with status `scheduled`.
  /// Throws [StateError] if the caller is not the program owner,
  /// or if the athlete is not enrolled (for assignable programs).
  /// Returns the generated document ID.
  Future<String> assignWorkout({
    required String programId,
    required String athleteId,
    required String workoutTemplateId,
    required int workoutTemplateVersion,
    required String scheduledDate,
    required WorkoutType workoutType,
    required String assignedBy,
  }) async {
    final authorization = await _verifyCanAssign(
      programId: programId,
      athleteId: athleteId,
      assignedBy: assignedBy,
    );
    if (authorization.selfProgramVersion != null) {
      await _verifyWorkoutInProgram(
        programId: programId,
        programVersion: authorization.selfProgramVersion!,
        workoutTemplateId: workoutTemplateId,
        workoutTemplateVersion: workoutTemplateVersion,
      );
    }
    final docRef = _collection.doc();
    await docRef.set({
      'programId': programId,
      'programOwnerId': authorization.ownerId,
      'programVersion': authorization.selfProgramVersion ?? 0,
      'programEntryId': null,
      'programEntrySortOrder': null,
      'athleteProgramInstanceId': null,
      'programAssignmentId': null,
      'relationshipMode': null,
      'athleteId': athleteId,
      'workoutTemplateId': workoutTemplateId,
      'workoutTemplateVersion': workoutTemplateVersion,
      'scheduledDate': scheduledDate,
      'scheduledAt': Timestamp.fromDate(DateTime.parse(scheduledDate).toUtc()),
      'workoutType': workoutType.name,
      'assignedBy': assignedBy,
      'assignedAt': FieldValue.serverTimestamp(),
      'status': WorkoutInstanceStatus.scheduled.name,
      'completedAt': null,
      'missedAt': null,
      'rpe': null,
      'durationMinutes': null,
      'loadPoints': null,
      'loadPointsOverride': null,
      'loadPointsOverriddenBy': null,
      'loadPointsOverriddenAt': null,
      'loadModelVersion': 1,
      'loadStrategyId': null,
      'recurrence': null,
      'isRecurrenceRoot': false,
      'recurrenceRootId': null,
      'actualsStorageFormat': 'slotResultsSubcollection',
      'actualSlotIds': <String>[],
      'actuals': <Map<String, dynamic>>[],
      'athleteNotes': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Assigns a recurring series of workouts based on a recurrence pattern.
  ///
  /// Expands the recurrence into individual dates, creates a batch of
  /// workout instances. The first instance is the "root" with
  /// [isRecurrenceRoot] = true; all others reference it via
  /// [recurrenceRootId]. Returns the number of instances created.
  ///
  /// Firestore batch writes are limited to 500 operations, which is
  /// well within the [Recurrence.maxInstances] cap of 364.
  Future<int> assignRecurringWorkouts({
    required String programId,
    required String athleteId,
    required String workoutTemplateId,
    required int workoutTemplateVersion,
    required String startDate,
    required WorkoutType workoutType,
    required String assignedBy,
    required Recurrence recurrence,
  }) async {
    recurrence.validate();

    final authorization = await _verifyCanAssign(
      programId: programId,
      athleteId: athleteId,
      assignedBy: assignedBy,
    );
    if (authorization.selfProgramVersion != null) {
      await _verifyWorkoutInProgram(
        programId: programId,
        programVersion: authorization.selfProgramVersion!,
        workoutTemplateId: workoutTemplateId,
        workoutTemplateVersion: workoutTemplateVersion,
      );
    }

    final dates = expandRecurrence(
      startDate: startDate,
      pattern: recurrence.pattern,
      endDate: recurrence.endDate,
      daysOfWeek: recurrence.daysOfWeek,
      intervalDays: recurrence.intervalDays,
    );

    if (dates.isEmpty) return 0;

    final batch = _firestore.batch();
    final rootRef = _collection.doc();
    final recurrenceMap = recurrence.toMap();

    // Create root instance (first date)
    batch.set(rootRef, {
      'programId': programId,
      'programOwnerId': authorization.ownerId,
      'programVersion': authorization.selfProgramVersion ?? 0,
      'athleteProgramInstanceId': null,
      'programAssignmentId': null,
      'relationshipMode': null,
      'athleteId': athleteId,
      'workoutTemplateId': workoutTemplateId,
      'workoutTemplateVersion': workoutTemplateVersion,
      'scheduledDate': dates[0],
      'scheduledAt': Timestamp.fromDate(DateTime.parse(dates[0]).toUtc()),
      'workoutType': workoutType.name,
      'assignedBy': assignedBy,
      'assignedAt': FieldValue.serverTimestamp(),
      'status': WorkoutInstanceStatus.scheduled.name,
      'completedAt': null,
      'missedAt': null,
      'rpe': null,
      'durationMinutes': null,
      'loadPoints': null,
      'loadPointsOverride': null,
      'loadPointsOverriddenBy': null,
      'loadPointsOverriddenAt': null,
      'loadModelVersion': 1,
      'loadStrategyId': null,
      'recurrence': recurrenceMap,
      'isRecurrenceRoot': true,
      'recurrenceRootId': null,
      'actualsStorageFormat': 'slotResultsSubcollection',
      'actualSlotIds': <String>[],
      'actuals': <Map<String, dynamic>>[],
      'athleteNotes': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Create child instances (remaining dates)
    for (var i = 1; i < dates.length; i++) {
      final childRef = _collection.doc();
      batch.set(childRef, {
        'programId': programId,
        'programOwnerId': authorization.ownerId,
        'programVersion': authorization.selfProgramVersion ?? 0,
        'athleteProgramInstanceId': null,
        'programAssignmentId': null,
        'relationshipMode': null,
        'athleteId': athleteId,
        'workoutTemplateId': workoutTemplateId,
        'workoutTemplateVersion': workoutTemplateVersion,
        'scheduledDate': dates[i],
        'scheduledAt': Timestamp.fromDate(DateTime.parse(dates[i]).toUtc()),
        'workoutType': workoutType.name,
        'assignedBy': assignedBy,
        'assignedAt': FieldValue.serverTimestamp(),
        'status': WorkoutInstanceStatus.scheduled.name,
        'completedAt': null,
        'missedAt': null,
        'rpe': null,
        'durationMinutes': null,
        'loadPoints': null,
        'loadPointsOverride': null,
        'loadPointsOverriddenBy': null,
        'loadPointsOverriddenAt': null,
        'loadModelVersion': 1,
        'loadStrategyId': null,
        'recurrence': recurrenceMap,
        'isRecurrenceRoot': false,
        'recurrenceRootId': rootRef.id,
        'actualsStorageFormat': 'slotResultsSubcollection',
        'actualSlotIds': <String>[],
        'actuals': <Map<String, dynamic>>[],
        'athleteNotes': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return dates.length;
  }

  /// Assigns an entire published program to an athlete starting on a date.
  ///
  /// Materializes every [ProgramScheduleEntry] of the program's current
  /// published version into a workout instance at
  /// `scheduledDate = startDate + dayOffset`. All created instances share a
  /// single [WorkoutInstance.programAssignmentId] so the block can later be
  /// cancelled or rescheduled together, and record the [programVersion] they
  /// were materialized from (an immutable snapshot — editing the program
  /// afterwards does not change already-assigned athletes).
  ///
  /// For assignable programs the athlete is auto-enrolled if not already
  /// enrolled. For personal programs only self-assignment is allowed.
  ///
  /// Throws [StateError] if the caller is not the program owner, if the
  /// program has no published version, or for a personal program assigned to
  /// someone other than the owner. Returns the assignment id and instance
  /// count.
  Future<ProgramAssignmentResult> assignProgram({
    required String programId,
    required String athleteId,
    required String startDate,
    required String assignedBy,
    ProgramRelationshipMode relationshipMode =
        ProgramRelationshipMode.subscribed,
    String? idempotencyKey,
  }) async {
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(startDate)) {
      throw ArgumentError(
        'startDate must be ISO 8601 date format (YYYY-MM-DD)',
      );
    }
    if (idempotencyKey != null &&
        (idempotencyKey.isEmpty ||
            idempotencyKey.contains('/') ||
            idempotencyKey.length > 200)) {
      throw ArgumentError(
        'idempotencyKey must be 1-200 characters and cannot contain "/"',
      );
    }
    final assignmentId = idempotencyKey == null
        ? _programInstances.doc().id
        : '$programId-$athleteId-$idempotencyKey';
    final instanceRef = _programInstances.doc(assignmentId);
    final existing = await instanceRef.get();
    if (existing.exists) {
      final data = existing.data()!;
      final requestedMode = assignedBy == athleteId
          ? ProgramRelationshipMode.copied
          : relationshipMode;
      final matches = data['materializationKey'] == idempotencyKey &&
          data['athleteOwnerId'] == athleteId &&
          data['assigningTrainerId'] == assignedBy &&
          data['sourceProgramId'] == programId &&
          data['startDate'] == startDate &&
          data['relationshipMode'] == requestedMode.name;
      if (!matches) {
        throw StateError(
          'Idempotency key is already used by a different assignment',
        );
      }
      return ProgramAssignmentResult(
        programInstanceId: assignmentId,
        instanceCount: (data['workoutCount'] as int?) ?? 0,
      );
    }

    final programRef = _firestore.collection('programs').doc(programId);
    final programDoc = await programRef.get();
    if (!programDoc.exists) {
      throw StateError('Program $programId not found');
    }
    final programData = programDoc.data()!;
    final ownerId = programData['ownerId'] as String?;
    final type = programData['type'] as String?;
    final currentVersion = (programData['currentVersion'] as int?) ?? 0;

    if (ownerId != assignedBy) {
      throw StateError(
        'User $assignedBy is not the owner of program $programId',
      );
    }
    if (currentVersion == 0) {
      throw StateError('Program $programId has no published version to assign');
    }

    var effectiveMode = relationshipMode;
    if (type == ProgramType.personal.name) {
      if (athleteId != assignedBy) {
        throw StateError('Personal programs only allow self-assignment');
      }
      effectiveMode = ProgramRelationshipMode.copied;
    } else {
      await _verifyActiveRelationship(ownerId!, athleteId);
    }

    final versionDoc = await programRef
        .collection('programVersions')
        .doc(currentVersion.toString())
        .get();
    final entries =
        (versionDoc.data()?['entries'] as List<dynamic>?) ?? <dynamic>[];
    if (entries.isEmpty) {
      throw StateError(
        'Program $programId version $currentVersion has no schedule entries',
      );
    }
    if (entries.length > 497) {
      throw StateError(
        'Program assignment exceeds the 497-workout atomic write limit',
      );
    }

    // Resolve each referenced workout template's type for load metrics.
    final templateIds = <String>{
      for (final e in entries)
        (e as Map<String, dynamic>)['workoutTemplateId'] as String? ?? '',
    }..removeWhere((id) => id.isEmpty);
    final typeByTemplate = <String, WorkoutType>{};
    await Future.wait(
      templateIds.map((tid) async {
        final tDoc =
            await _firestore.collection('workoutTemplates').doc(tid).get();
        typeByTemplate[tid] = _parseWorkoutType(
          tDoc.data()?['workoutType'] as String?,
        );
      }),
    );

    final expectedEndDate = entries
        .map((raw) => (raw as Map<String, dynamic>)['dayOffset'] as int? ?? 0)
        .map((offset) => addDays(startDate, offset))
        .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    final batch = _firestore.batch();
    final enrollmentRef =
        _firestore.collection('enrollments').doc('${programId}_$athleteId');
    final enrollment = await enrollmentRef.get();
    if (type != ProgramType.personal.name &&
        (!enrollment.exists || enrollment.data()?['status'] != 'active')) {
      batch.set(enrollmentRef, {
        'programId': programId,
        'athleteId': athleteId,
        'addedAt': FieldValue.serverTimestamp(),
        'addedBy': assignedBy,
        'removedAt': null,
        'removedBy': null,
        'status': EnrollmentStatus.active.name,
        'createdBy': assignedBy,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': assignedBy,
        'deletedAt': null,
        'deletedBy': null,
      });
    }
    batch.set(instanceRef, {
      'athleteOwnerId': athleteId,
      'assigningTrainerId': assignedBy,
      'sourceProgramId': programId,
      'sourceProgramVersion': currentVersion,
      'relationshipMode': effectiveMode.name,
      'startDate': startDate,
      'expectedEndDate': expectedEndDate,
      'workoutCount': entries.length,
      'status': AthleteProgramInstanceStatus.active.name,
      'linkedAt': effectiveMode == ProgramRelationshipMode.subscribed
          ? FieldValue.serverTimestamp()
          : null,
      'unlinkedAt': null,
      'unlinkReason': null,
      'materializationKey': idempotencyKey,
      'propagationState': ProgramPropagationState.complete.name,
      'propagationTargetVersion': currentVersion,
      'propagationAttempt': 0,
      'propagationStartedAt': null,
      'propagationCompletedAt': FieldValue.serverTimestamp(),
      'propagationFailedAt': null,
      'propagationError': null,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': assignedBy,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': assignedBy,
      'deletedAt': null,
      'deletedBy': null,
    });

    for (var index = 0; index < entries.length; index++) {
      final raw = entries[index];
      final entry = raw as Map<String, dynamic>;
      final templateId = entry['workoutTemplateId'] as String? ?? '';
      final templateVersion = (entry['workoutTemplateVersion'] as int?) ?? 1;
      final dayOffset = (entry['dayOffset'] as int?) ?? 0;
      final scheduledDate = addDays(startDate, dayOffset);
      final workoutType = typeByTemplate[templateId] ?? WorkoutType.fullBody;
      final entryId = entry['entryId'] as String? ??
          legacyProgramScheduleEntryId((entry['sortOrder'] as int?) ?? index);

      final docRef = _collection.doc('$assignmentId-$index');
      batch.set(docRef, {
        'programId': programId,
        'programOwnerId': ownerId,
        'programVersion': currentVersion,
        'programEntryId': entryId,
        'programEntrySortOrder': (entry['sortOrder'] as int?) ?? index,
        'athleteProgramInstanceId': assignmentId,
        'programAssignmentId': assignmentId,
        'relationshipMode': effectiveMode.name,
        'athleteId': athleteId,
        'workoutTemplateId': templateId,
        'workoutTemplateVersion': templateVersion,
        'scheduledDate': scheduledDate,
        'scheduledAt': Timestamp.fromDate(
          DateTime.parse(scheduledDate).toUtc(),
        ),
        'workoutType': workoutType.name,
        'assignedBy': assignedBy,
        'assignedAt': FieldValue.serverTimestamp(),
        'status': WorkoutInstanceStatus.scheduled.name,
        'completedAt': null,
        'missedAt': null,
        'rpe': null,
        'durationMinutes': null,
        'loadPoints': null,
        'loadPointsOverride': null,
        'loadPointsOverriddenBy': null,
        'loadPointsOverriddenAt': null,
        'loadModelVersion': 1,
        'loadStrategyId': null,
        'recurrence': null,
        'isRecurrenceRoot': false,
        'recurrenceRootId': null,
        'actualsStorageFormat': 'slotResultsSubcollection',
        'actualSlotIds': <String>[],
        'actuals': <Map<String, dynamic>>[],
        'athleteNotes': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return ProgramAssignmentResult(
      programInstanceId: assignmentId,
      instanceCount: entries.length,
    );
  }

  /// Cancels all still-scheduled instances belonging to a program assignment.
  ///
  /// Completed and missed instances are preserved. Returns the number of
  /// instances cancelled.
  Future<int> cancelProgramAssignment({
    required String programAssignmentId,
    required String ownerId,
  }) async {
    final assignmentDocs = await _ownedAssignmentDocs(
      programAssignmentId: programAssignmentId,
      ownerId: ownerId,
    );
    final targets = assignmentDocs
        .where(
          (doc) =>
              doc.data()['status'] == WorkoutInstanceStatus.scheduled.name &&
              (doc.data()['scheduledDate'] as String? ?? '').compareTo(
                    _today,
                  ) >=
                  0,
        )
        .toList();

    final instanceRef = _programInstances.doc(programAssignmentId);
    final instance = await instanceRef.get();
    for (var start = 0; start < targets.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, targets.length);
      for (final doc in targets.sublist(start, end)) {
        batch.update(doc.reference, {
          'status': WorkoutInstanceStatus.cancelled.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    if (instance.exists && instance.data() != null) {
      await _refreshProgramInstanceLifecycle(
        programAssignmentId,
        instance.data()!['athleteOwnerId'] as String,
        ownerId,
      );
    }
    return targets.length;
  }

  /// Permanently deletes the still-incomplete instances of a program
  /// assignment (everything except completed workouts, so an athlete's
  /// completion history is preserved).
  ///
  /// Used to undo an assignment that was made by mistake. Unlike
  /// [cancelProgramAssignment] this is a hard delete, so no audit trail
  /// remains.
  ///
  /// Defense-in-depth: filters by [ownerId] so the query is provably limited
  /// to instances the caller assigned (matching the read rule). Returns the
  /// number of instances deleted.
  Future<int> deleteIncompleteProgramAssignment({
    required String programAssignmentId,
    required String ownerId,
  }) async {
    final assignmentDocs = await _ownedAssignmentDocs(
      programAssignmentId: programAssignmentId,
      ownerId: ownerId,
    );
    final targets = assignmentDocs
        .where(
          (doc) =>
              doc.data()['status'] == WorkoutInstanceStatus.scheduled.name &&
              (doc.data()['scheduledDate'] as String? ?? '').compareTo(
                    _today,
                  ) >=
                  0,
        )
        .toList();
    await _deleteInstancesWithResults(targets);
    final instanceRef = _programInstances.doc(programAssignmentId);
    final instance = await instanceRef.get();
    if (instance.exists && instance.data() != null) {
      await _refreshProgramInstanceLifecycle(
        programAssignmentId,
        instance.data()!['athleteOwnerId'] as String,
        ownerId,
      );
    }
    return targets.length;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _ownedAssignmentDocs({
    required String programAssignmentId,
    required String ownerId,
  }) async {
    final firstClass = await _programInstances.doc(programAssignmentId).get();
    if (firstClass.exists) {
      final data = firstClass.data()!;
      final athleteId = data['athleteOwnerId'] as String?;
      final trainerId = data['assigningTrainerId'] as String?;
      if (athleteId == null ||
          athleteId.isEmpty ||
          trainerId == null ||
          trainerId.isEmpty) {
        throw StateError(
          'Assignment $programAssignmentId has invalid ownership metadata',
        );
      }
      if (ownerId != athleteId && ownerId != trainerId) {
        throw StateError(
          'User $ownerId does not own assignment $programAssignmentId',
        );
      }
      if (ownerId == trainerId && trainerId != athleteId) {
        await _verifyActiveRelationship(trainerId, athleteId);
      }
      Query<Map<String, dynamic>> query = _collection
          .where('athleteProgramInstanceId', isEqualTo: programAssignmentId)
          .where('athleteId', isEqualTo: athleteId);
      if (ownerId == trainerId) {
        query = query.where('programOwnerId', isEqualTo: trainerId);
      }
      final snapshot = await query.get();
      return snapshot.docs;
    }

    Future<QuerySnapshot<Map<String, dynamic>>> legacyQuery(String ownerField) {
      return _collection
          .where('programAssignmentId', isEqualTo: programAssignmentId)
          .where(ownerField, isEqualTo: ownerId)
          .get();
    }

    final snapshots = await Future.wait([
      legacyQuery('athleteId'),
      legacyQuery('programOwnerId'),
      legacyQuery('assignedBy'),
    ]);
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final snapshot in snapshots)
        for (final doc in snapshot.docs) doc.id: doc,
    };
    if (byId.isEmpty) {
      throw StateError(
        'User $ownerId does not own assignment $programAssignmentId',
      );
    }
    for (final doc in byId.values) {
      final data = doc.data();
      if (data['athleteId'] != ownerId &&
          data['programOwnerId'] != ownerId &&
          data['assignedBy'] != ownerId) {
        throw StateError(
          'User $ownerId does not own assignment $programAssignmentId',
        );
      }
    }
    return byId.values.toList();
  }

  Future<void> _deleteInstancesWithResults(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> instances,
  ) async {
    var batch = _firestore.batch();
    var operationCount = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (operationCount == 0 || (!force && operationCount < 450)) return;
      await batch.commit();
      batch = _firestore.batch();
      operationCount = 0;
    }

    for (final instance in instances) {
      final results = await instance.reference.collection('slotResults').get();
      for (final result in results.docs) {
        batch.delete(result.reference);
        operationCount++;
        await commitIfNeeded();
      }
      batch.delete(instance.reference);
      operationCount++;
      await commitIfNeeded();
    }
    await commitIfNeeded(force: true);
  }

  /// Permanently deletes a single workout instance.
  ///
  /// Defense-in-depth: verifies [ownerId] assigned the instance or owns it as
  /// the athlete. Throws [StateError] otherwise or if it does not exist.
  Future<void> deleteInstance({
    required String instanceId,
    required String ownerId,
  }) async {
    final instance = await getById(instanceId);
    if (instance == null) {
      throw StateError('Instance $instanceId not found');
    }
    await _verifyCanManageScheduledInstance(instance, ownerId);
    final instanceRef = _collection.doc(instanceId);
    final programInstanceId = instance.resolvedProgramInstanceId;
    final results = await instanceRef.collection('slotResults').get();
    final batch = _firestore.batch();
    for (final result in results.docs) {
      batch.delete(result.reference);
    }
    batch.delete(instanceRef);
    await batch.commit();
    await _refreshProgramInstanceLifecycle(
      programInstanceId,
      instance.athleteId,
      ownerId,
    );
  }

  /// Cancels all future scheduled instances in a recurrence group.
  ///
  /// Finds all instances with the given [recurrenceRootId] (or the root
  /// itself) that are still scheduled, and cancels them.
  Future<int> cancelRecurrence({
    required String recurrenceRootId,
    required String ownerId,
  }) async {
    final rootDoc = await _collection.doc(recurrenceRootId).get();
    if (!rootDoc.exists || rootDoc.data() == null) {
      throw StateError('Recurrence $recurrenceRootId not found');
    }
    final rootData = rootDoc.data()!;
    final athleteId = rootData['athleteId'] as String?;
    final trainerId = rootData['programOwnerId'] as String? ??
        rootData['assignedBy'] as String?;
    if (athleteId != ownerId && trainerId != ownerId) {
      throw StateError(
        'User $ownerId does not own recurrence $recurrenceRootId',
      );
    }
    if (trainerId == ownerId && athleteId != ownerId) {
      await _verifyActiveRelationship(trainerId!, athleteId!);
    }

    Future<QuerySnapshot<Map<String, dynamic>>> childrenFor(String field) {
      return _collection
          .where('recurrenceRootId', isEqualTo: recurrenceRootId)
          .where('athleteId', isEqualTo: athleteId)
          .where(field, isEqualTo: ownerId)
          .where('status', isEqualTo: WorkoutInstanceStatus.scheduled.name)
          .get();
    }

    final childSnapshots = athleteId == ownerId
        ? [
            await _collection
                .where('recurrenceRootId', isEqualTo: recurrenceRootId)
                .where('athleteId', isEqualTo: athleteId)
                .where(
                  'status',
                  isEqualTo: WorkoutInstanceStatus.scheduled.name,
                )
                .get(),
          ]
        : [
            await childrenFor('programOwnerId'),
            await childrenFor('assignedBy'),
          ];
    final childrenById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final snapshot in childSnapshots)
        for (final doc in snapshot.docs) doc.id: doc,
    };
    final childDocs = childrenById.values.toList();
    for (final doc in childDocs) {
      final data = doc.data();
      if (data['athleteId'] != ownerId &&
          data['programOwnerId'] != ownerId &&
          data['assignedBy'] != ownerId) {
        throw StateError(
          'Workout instance ownership mismatch in recurrence '
          '$recurrenceRootId',
        );
      }
    }

    final targets = <DocumentReference<Map<String, dynamic>>>[];
    final programInstances = <String>{};
    for (final doc in childDocs) {
      if ((doc.data()['scheduledDate'] as String? ?? '').compareTo(_today) <
          0) {
        continue;
      }
      targets.add(doc.reference);
      final programInstanceId =
          doc.data()['athleteProgramInstanceId'] as String?;
      if (programInstanceId != null) {
        programInstances.add(programInstanceId);
      }
    }

    if (rootDoc.exists &&
        rootDoc.data()?['status'] == WorkoutInstanceStatus.scheduled.name &&
        (rootData['scheduledDate'] as String? ?? '').compareTo(_today) >= 0) {
      targets.add(rootDoc.reference);
      final programInstanceId = rootData['athleteProgramInstanceId'] as String?;
      if (programInstanceId != null) {
        programInstances.add(programInstanceId);
      }
    }
    for (var start = 0; start < targets.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, targets.length);
      for (final target in targets.sublist(start, end)) {
        batch.update(target, {
          'status': WorkoutInstanceStatus.cancelled.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    for (final programInstanceId in programInstances) {
      await _refreshProgramInstanceLifecycle(
        programInstanceId,
        athleteId!,
        ownerId,
      );
    }
    await recoverProgramInstanceLifecycles(
      athleteId: athleteId!,
      actorId: ownerId,
    );
    return targets.length;
  }

  /// Marks a workout instance as completed by the athlete.
  ///
  /// Sets status to `completed`, writes `completedAt`, and records
  /// RPE, duration, and per-exercise actuals.
  Future<void> completeWorkout({
    required String instanceId,
    required String athleteId,
    required int rpe,
    required int durationMinutes,
    required List<ExerciseActual> actuals,
    double? loadPoints,
    String? loadStrategyId,
    String? athleteNotes,
  }) async {
    final stored = await _collection.doc(instanceId).get();
    if (!stored.exists || stored.data() == null) {
      throw StateError('Instance $instanceId not found');
    }
    if (stored.data()!['athleteId'] != athleteId) {
      throw StateError('User $athleteId does not own instance $instanceId');
    }
    if (stored.data()!['status'] == WorkoutInstanceStatus.completed.name) {
      await _refreshProgramInstanceCompletion(instanceId, athleteId);
      return;
    }
    if (stored.data()!['status'] != WorkoutInstanceStatus.scheduled.name) {
      throw StateError('Instance $instanceId must be scheduled');
    }
    final actualsBySlot = await _prepareSlotResults(
      instanceId: instanceId,
      actuals: actuals,
    );
    await _writeCompletion(
      instanceId: instanceId,
      athleteId: athleteId,
      requiredStatus: WorkoutInstanceStatus.scheduled,
      actualsBySlot: actualsBySlot,
      parentFields: {
        'status': WorkoutInstanceStatus.completed.name,
        'completedAt': FieldValue.serverTimestamp(),
        'rpe': rpe,
        'durationMinutes': durationMinutes,
        'loadPoints': loadPoints,
        'loadStrategyId': loadStrategyId,
        'athleteNotes': athleteNotes,
      },
    );
    await _refreshProgramInstanceCompletion(instanceId, athleteId);
  }

  Future<void> _refreshProgramInstanceCompletion(
    String workoutInstanceId,
    String athleteId,
  ) async {
    final workout = await _collection.doc(workoutInstanceId).get();
    final programInstanceId =
        workout.data()?['athleteProgramInstanceId'] as String?;
    await _refreshProgramInstanceLifecycle(
      programInstanceId,
      athleteId,
      athleteId,
    );
  }

  Future<void> _refreshProgramInstanceLifecycle(
    String? programInstanceId,
    String athleteId,
    String actorId,
  ) async {
    if (programInstanceId == null) return;
    final workouts = await _collection
        .where('athleteProgramInstanceId', isEqualTo: programInstanceId)
        .where('athleteId', isEqualTo: athleteId)
        .get();
    final hasIncomplete = workouts.docs.any(
      (doc) => doc.data()['status'] == WorkoutInstanceStatus.scheduled.name,
    );
    if (hasIncomplete) return;
    final hasCompletedOrMissed = workouts.docs.any((doc) {
      final status = doc.data()['status'];
      return status == WorkoutInstanceStatus.completed.name ||
          status == WorkoutInstanceStatus.missed.name;
    });
    final nextStatus = hasCompletedOrMissed
        ? AthleteProgramInstanceStatus.completed
        : AthleteProgramInstanceStatus.cancelled;

    final ref = _programInstances.doc(programInstanceId);
    await _firestore.runTransaction<void>((transaction) async {
      final instance = await transaction.get(ref);
      if (!instance.exists || instance.data() == null) {
        throw StateError('Program instance $programInstanceId not found');
      }
      final data = instance.data()!;
      if (data['athleteOwnerId'] != athleteId) {
        throw StateError(
          'User $athleteId does not own program instance $programInstanceId',
        );
      }
      if (data['status'] == nextStatus.name) {
        return;
      }
      if (data['status'] != AthleteProgramInstanceStatus.active.name) {
        throw StateError('Only active program instances can be completed');
      }
      transaction.update(ref, {
        'status': nextStatus.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': actorId,
      });
    });
  }

  /// Cancels all future scheduled workout instances for a program-athlete pair.
  ///
  /// Used when an athlete is removed from a program. Only cancels instances
  /// with status `scheduled` — completed and missed instances are preserved.
  Future<int> cancelFutureInstances({
    required String programId,
    required String athleteId,
    required String ownerId,
  }) async {
    final program =
        await _firestore.collection('programs').doc(programId).get();
    if (!program.exists) {
      throw StateError('Program $programId not found');
    }
    final programOwnerId = program.data()?['ownerId'] as String?;
    if (programOwnerId != ownerId && athleteId != ownerId) {
      throw StateError('User $ownerId is not the owner of program $programId');
    }
    if (programOwnerId == ownerId && athleteId != ownerId) {
      await _verifyActiveRelationship(ownerId, athleteId);
    }
    Future<QuerySnapshot<Map<String, dynamic>>> workoutsFor(String field) {
      return _collection
          .where('programId', isEqualTo: programId)
          .where('athleteId', isEqualTo: athleteId)
          .where(field, isEqualTo: ownerId)
          .where('status', isEqualTo: WorkoutInstanceStatus.scheduled.name)
          .get();
    }

    final snapshots = ownerId == athleteId
        ? [
            await _collection
                .where('programId', isEqualTo: programId)
                .where('athleteId', isEqualTo: athleteId)
                .where(
                  'status',
                  isEqualTo: WorkoutInstanceStatus.scheduled.name,
                )
                .get(),
          ]
        : [
            await workoutsFor('programOwnerId'),
            await workoutsFor('assignedBy'),
          ];
    final snapshotDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final snapshot in snapshots)
        for (final doc in snapshot.docs) doc.id: doc,
    }.values;

    final targets = snapshotDocs
        .where(
          (doc) =>
              (doc.data()['scheduledDate'] as String? ?? '').compareTo(
                _today,
              ) >=
              0,
        )
        .toList();
    for (var start = 0; start < targets.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, targets.length);
      for (final doc in targets.sublist(start, end)) {
        batch.update(doc.reference, {
          'status': WorkoutInstanceStatus.cancelled.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    final programInstances = targets
        .map((doc) => doc.data()['athleteProgramInstanceId'] as String?)
        .whereType<String>()
        .toSet();
    for (final programInstanceId in programInstances) {
      await _refreshProgramInstanceLifecycle(
        programInstanceId,
        athleteId,
        ownerId,
      );
    }
    await recoverProgramInstanceLifecycles(
      athleteId: athleteId,
      actorId: ownerId,
    );
    return targets.length;
  }

  /// Streams workout instances for an athlete within a date range.
  ///
  /// Used for the athlete's calendar view.
  Stream<List<WorkoutInstance>> watchSchedule({
    required String athleteId,
    required String startDate,
    required String endDate,
  }) {
    return _collection
        .where('athleteId', isEqualTo: athleteId)
        .where('scheduledDate', isGreaterThanOrEqualTo: startDate)
        .where('scheduledDate', isLessThanOrEqualTo: endDate)
        .orderBy('scheduledDate')
        .snapshots()
        .asyncMap(_instancesFromSnapshot);
  }

  /// Streams immutable terminal records and any overdue scheduled workouts.
  ///
  /// The query stays athlete-scoped for Firestore authorization and uses the
  /// existing `(athleteId, scheduledDate)` index. Filtering the historical
  /// subset client-side keeps legacy terminal records visible without a
  /// second query or a status migration.
  Stream<List<WorkoutInstance>> watchHistory({
    required String athleteId,
  }) {
    final source = _collection
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('scheduledDate', descending: true)
        .snapshots()
        .asyncMap(_instancesFromSnapshot);
    late StreamController<List<WorkoutInstance>> controller;
    StreamSubscription<List<WorkoutInstance>>? subscription;
    Timer? dayRollover;
    var latest = <WorkoutInstance>[];

    void emit() {
      final today = _localToday;
      controller.add(
        latest
            .where(
              (instance) =>
                  !instance.isScheduled ||
                  instance.scheduledDate.compareTo(today) < 0,
            )
            .toList(),
      );
    }

    void scheduleDayRollover() {
      dayRollover?.cancel();
      dayRollover = Timer(_untilNextLocalDay, () {
        emit();
        scheduleDayRollover();
      });
    }

    controller = StreamController<List<WorkoutInstance>>(
      onListen: () {
        subscription = source.listen(
          (instances) {
            latest = instances;
            emit();
          },
          onError: controller.addError,
        );
        scheduleDayRollover();
      },
      onCancel: () async {
        dayRollover?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// Streams workout instances for a specific program-athlete pair.
  ///
  /// Used by the owner or athlete to view a schedule within a program.
  Stream<List<WorkoutInstance>> watchProgramSchedule({
    required String programId,
    required String athleteId,
    required String callerId,
    String? startDate,
    String? endDate,
  }) {
    Stream<List<WorkoutInstance>> watchOwnerField(String? field) {
      Query<Map<String, dynamic>> query = _collection
          .where('programId', isEqualTo: programId)
          .where('athleteId', isEqualTo: athleteId);
      if (field != null) {
        query = query.where(field, isEqualTo: callerId);
      }
      if (startDate != null) {
        query = query.where('scheduledDate', isGreaterThanOrEqualTo: startDate);
      }
      if (endDate != null) {
        query = query.where('scheduledDate', isLessThanOrEqualTo: endDate);
      }
      return query
          .orderBy('scheduledDate', descending: true)
          .snapshots()
          .asyncMap(_instancesFromSnapshot);
    }

    if (callerId == athleteId) {
      return watchOwnerField(null);
    }
    return _mergeInstanceStreams([
      watchOwnerField('programOwnerId'),
      watchOwnerField('assignedBy'),
    ], descending: true);
  }

  /// Streams every instance in [ownerId]'s programs for [athleteId].
  ///
  /// New documents are queried by immutable `programOwnerId`, which includes
  /// trainer- and athlete-assigned workouts. A legacy `assignedBy` query is
  /// merged so pre-migration trainer assignments remain visible.
  Stream<List<WorkoutInstance>> watchAthleteCalendar({
    required String ownerId,
    required String athleteId,
    required String startDate,
    required String endDate,
  }) {
    Stream<List<WorkoutInstance>> watchField(String field) => _collection
        .where(field, isEqualTo: ownerId)
        .where('athleteId', isEqualTo: athleteId)
        .where('scheduledDate', isGreaterThanOrEqualTo: startDate)
        .where('scheduledDate', isLessThanOrEqualTo: endDate)
        .orderBy('scheduledDate')
        .snapshots()
        .asyncMap(_instancesFromSnapshot);

    return _mergeInstanceStreams([
      watchField('programOwnerId'),
      watchField('assignedBy'),
    ]);
  }

  Stream<List<WorkoutInstance>> _mergeInstanceStreams(
    List<Stream<List<WorkoutInstance>>> streams, {
    bool descending = false,
  }) {
    late StreamController<List<WorkoutInstance>> controller;
    final subscriptions = <StreamSubscription<List<WorkoutInstance>>>[];
    final latest = List.generate(streams.length, (_) => <WorkoutInstance>[]);
    final loaded = List.filled(streams.length, false);

    void emit() {
      if (loaded.any((value) => !value)) return;
      final byId = <String, WorkoutInstance>{
        for (final instances in latest)
          for (final instance in instances) instance.id: instance,
      };
      final combined = byId.values.toList()
        ..sort(
          (a, b) => descending
              ? b.scheduledDate.compareTo(a.scheduledDate)
              : a.scheduledDate.compareTo(b.scheduledDate),
        );
      controller.add(combined);
    }

    controller = StreamController<List<WorkoutInstance>>(
      onListen: () {
        for (var i = 0; i < streams.length; i += 1) {
          subscriptions.add(
            streams[i].listen((instances) {
              latest[i] = instances;
              loaded[i] = true;
              emit();
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Reconciles active parents after an interrupted child terminal mutation.
  Future<int> recoverProgramInstanceLifecycles({
    required String athleteId,
    required String actorId,
  }) async {
    Query<Map<String, dynamic>> query = _programInstances
        .where('athleteOwnerId', isEqualTo: athleteId)
        .where('status', isEqualTo: AthleteProgramInstanceStatus.active.name);
    if (actorId != athleteId) {
      await _verifyActiveRelationship(actorId, athleteId);
      query = query.where('assigningTrainerId', isEqualTo: actorId);
    }
    final active = await query.get();
    for (final instance in active.docs) {
      final data = instance.data();
      if (data['athleteOwnerId'] != athleteId ||
          (actorId != athleteId && data['assigningTrainerId'] != actorId)) {
        throw StateError('Program instance ${instance.id} ownership mismatch');
      }
      await _refreshProgramInstanceLifecycle(instance.id, athleteId, actorId);
    }
    return active.docs.length;
  }

  /// Adds `programOwnerId` to legacy instances for an active program.
  ///
  /// Defense-in-depth: [actorId] must be the athlete, and every updated
  /// instance is verified to belong to that athlete and program.
  Future<int> backfillProgramOwnerId({
    required String programId,
    required String athleteId,
    required String actorId,
  }) async {
    if (actorId != athleteId) {
      throw StateError('Only the athlete can migrate their workout instances');
    }
    final programDoc =
        await _firestore.collection('programs').doc(programId).get();
    final programOwnerId = programDoc.data()?['ownerId'] as String?;
    if (programOwnerId == null || programOwnerId.isEmpty) {
      throw StateError('Program $programId has no owner');
    }

    final snapshot = await _collection
        .where('programId', isEqualTo: programId)
        .where('athleteId', isEqualTo: athleteId)
        .get();
    final targets = snapshot.docs.where((doc) {
      final data = doc.data();
      if (data['athleteId'] != actorId || data['programId'] != programId) {
        throw StateError('Workout instance ownership mismatch');
      }
      return data['programOwnerId'] == null;
    }).toList();

    for (var start = 0; start < targets.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, targets.length);
      for (final doc in targets.sublist(start, end)) {
        batch.update(doc.reference, {'programOwnerId': programOwnerId});
      }
      await batch.commit();
    }
    return targets.length;
  }

  /// Moves a scheduled instance to [newDate].
  ///
  /// Defense-in-depth: verifies [ownerId] assigned the instance and that it
  /// is still `scheduled` before writing. Throws [StateError] otherwise.
  /// Firestore rules remain the primary enforcement layer.
  Future<void> rescheduleInstance({
    required String instanceId,
    required String newDate,
    required String ownerId,
  }) async {
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(newDate)) {
      throw ArgumentError('newDate must be ISO 8601 date format (YYYY-MM-DD)');
    }
    if (newDate.compareTo(_today) < 0) {
      throw StateError('Past workouts cannot be rescheduled');
    }
    final instance = await getById(instanceId);
    if (instance == null) {
      throw StateError('Instance $instanceId not found');
    }
    await _verifyCanManageScheduledInstance(instance, ownerId);
    await _collection.doc(instanceId).update({
      'scheduledDate': newDate,
      'scheduledAt': Timestamp.fromDate(DateTime.parse(newDate).toUtc()),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cancels a single scheduled instance.
  ///
  /// Defense-in-depth: verifies [ownerId] assigned the instance and that it
  /// is still `scheduled`. Throws [StateError] otherwise.
  Future<void> cancelInstance({
    required String instanceId,
    required String ownerId,
  }) async {
    final instance = await getById(instanceId);
    if (instance == null) {
      throw StateError('Instance $instanceId not found');
    }
    if (instance.status == WorkoutInstanceStatus.cancelled) {
      if (instance.athleteId != ownerId &&
          instance.programOwnerId != ownerId &&
          instance.assignedBy != ownerId) {
        throw StateError('User $ownerId cannot manage instance $instanceId');
      }
      if (instance.athleteId != ownerId) {
        await _verifyActiveRelationship(ownerId, instance.athleteId);
      }
      await _refreshProgramInstanceLifecycle(
        instance.resolvedProgramInstanceId,
        instance.athleteId,
        ownerId,
      );
      return;
    }
    await _verifyCanManageScheduledInstance(instance, ownerId);
    await _collection.doc(instanceId).update({
      'status': WorkoutInstanceStatus.cancelled.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _refreshProgramInstanceLifecycle(
      instance.resolvedProgramInstanceId,
      instance.athleteId,
      ownerId,
    );
  }

  Future<void> _verifyCanManageScheduledInstance(
    WorkoutInstance instance,
    String actorId,
  ) async {
    if (instance.status != WorkoutInstanceStatus.scheduled) {
      throw StateError('Only scheduled instances can be changed');
    }
    if (instance.scheduledDate.compareTo(_today) < 0) {
      throw StateError('Past workouts are immutable');
    }
    if (instance.athleteId == actorId) {
      final programInstanceId = instance.resolvedProgramInstanceId;
      if (programInstanceId != null) {
        final programInstance =
            await _programInstances.doc(programInstanceId).get();
        if (programInstance.exists &&
            programInstance.data()?['relationshipMode'] !=
                ProgramRelationshipMode.copied.name) {
          throw StateError(
            'Convert the subscription to a copy before customizing it',
          );
        }
      }
      return;
    }

    final trainerId = instance.programOwnerId ?? instance.assignedBy;
    if (trainerId != actorId) {
      throw StateError('User $actorId cannot manage instance ${instance.id}');
    }
    await _verifyActiveRelationship(trainerId, instance.athleteId);
  }

  /// Returns a single workout instance by ID, or null.
  Future<WorkoutInstance?> getById(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return _fromDocument(doc);
  }

  // -- Serialization helpers --

  Future<List<WorkoutInstance>> _instancesFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return Future.wait(snapshot.docs.map(_fromDocument));
  }

  Future<WorkoutInstance> _fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data()!;
    final declaredSlotIds = data['actualSlotIds'];
    final Map<String, ExerciseActual> actualsBySlot;
    if (data['actualsStorageFormat'] == 'slotResultsSubcollection' &&
        declaredSlotIds is List &&
        declaredSlotIds.isNotEmpty) {
      final slotIds = declaredSlotIds.whereType<String>().toList();
      if (slotIds.length != declaredSlotIds.length) {
        throw StateError('Actual slot IDs must be strings');
      }
      actualsBySlot = await _readSlotResults(doc.reference, slotIds: slotIds);
    } else if (data['actualsStorageFormat'] == 'slotResultsSubcollection' &&
        declaredSlotIds is! List) {
      actualsBySlot = await _readSlotResults(doc.reference);
    } else {
      actualsBySlot = _parseActualsBySlot(data);
    }
    return _fromMap(data, doc.id, actualsBySlot: actualsBySlot);
  }

  WorkoutInstance _fromMap(
    Map<String, dynamic> data,
    String id, {
    required Map<String, ExerciseActual> actualsBySlot,
  }) {
    return WorkoutInstance(
      id: id,
      programId: data['programId'] as String? ?? '',
      programOwnerId: data['programOwnerId'] as String?,
      programVersion: (data['programVersion'] as int?) ?? 0,
      programEntryId: data['programEntryId'] as String?,
      programEntrySortOrder: data['programEntrySortOrder'] as int?,
      athleteProgramInstanceId: data['athleteProgramInstanceId'] as String?,
      programAssignmentId: data['programAssignmentId'] as String?,
      relationshipMode: _parseRelationshipMode(
        data['relationshipMode'] as String?,
      ),
      athleteId: data['athleteId'] as String? ?? '',
      workoutTemplateId: data['workoutTemplateId'] as String? ?? '',
      workoutTemplateVersion: (data['workoutTemplateVersion'] as int?) ?? 1,
      scheduledDate: data['scheduledDate'] as String? ?? '',
      assignedBy: data['assignedBy'] as String? ?? '',
      assignedAt: _toDateTime(data['assignedAt']),
      status: _parseStatus(data['status'] as String?),
      completedAt:
          data['completedAt'] != null ? _toDateTime(data['completedAt']) : null,
      missedAt: data['missedAt'] != null ? _toDateTime(data['missedAt']) : null,
      rpe: data['rpe'] as int?,
      durationMinutes: data['durationMinutes'] as int?,
      loadPoints: (data['loadPoints'] as num?)?.toDouble(),
      loadPointsOverride: (data['loadPointsOverride'] as num?)?.toDouble(),
      loadPointsOverriddenBy: data['loadPointsOverriddenBy'] as String?,
      loadPointsOverriddenAt: data['loadPointsOverriddenAt'] != null
          ? _toDateTime(data['loadPointsOverriddenAt'])
          : null,
      loadModelVersion: (data['loadModelVersion'] as int?) ?? 1,
      loadStrategyId: data['loadStrategyId'] as String?,
      workoutType: _parseWorkoutType(data['workoutType'] as String?),
      recurrence: data['recurrence'] != null
          ? _recurrenceFromMap(data['recurrence'] as Map<String, dynamic>)
          : null,
      isRecurrenceRoot: data['isRecurrenceRoot'] as bool? ?? false,
      recurrenceRootId: data['recurrenceRootId'] as String?,
      actualsBySlot: actualsBySlot,
      athleteNotes: data['athleteNotes'] as String?,
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> _actualToMap(ExerciseActual actual) {
    return {
      'exerciseId': actual.exerciseId,
      'mode': actual.mode.name,
      'sets': actual.sets,
      'reps': actual.reps,
      'durationSeconds': actual.durationSeconds,
      'weight': actual.weight,
      'restSeconds': actual.restSeconds,
      'notes': actual.notes,
    };
  }

  Future<Map<String, ExerciseActual>> _readSlotResults(
    DocumentReference<Map<String, dynamic>> instanceRef, {
    List<String>? slotIds,
  }) async {
    if (slotIds != null) {
      final documents = await Future.wait(
        slotIds.map(
          (slotId) => instanceRef.collection('slotResults').doc(slotId).get(),
        ),
      );
      final results = <String, ExerciseActual>{};
      for (final document in documents) {
        if (!document.exists || document.data() == null) {
          throw StateError('Missing result for slot ${document.id}');
        }
        results[document.id] = _actualFromMap(
          document.data()!,
          slotId: document.id,
        );
      }
      return results;
    }
    final snapshot = await instanceRef.collection('slotResults').get();
    return {
      for (final doc in snapshot.docs)
        doc.id: _actualFromMap(doc.data(), slotId: doc.id),
    };
  }

  Map<String, ExerciseActual> _parseActualsBySlot(Map<String, dynamic> data) {
    final current = data['actualsBySlot'];
    if (current is Map<String, dynamic>) {
      final parsed = <String, ExerciseActual>{};
      for (final entry in current.entries) {
        if (entry.value is! Map) {
          throw StateError('Slot result ${entry.key} must be a map');
        }
        parsed[entry.key] = _actualFromMap(
          Map<String, dynamic>.from(entry.value as Map),
          slotId: entry.key,
        );
      }
      return parsed;
    }
    final legacy = data['actuals'];
    if (legacy is! List) return {};
    final parsed = <String, ExerciseActual>{};
    for (var index = 0; index < legacy.length; index++) {
      final raw = legacy[index];
      if (raw is! Map) {
        throw StateError('Legacy actual at index $index must be a map');
      }
      final slotId = legacyExerciseSlotId(index);
      parsed[slotId] = _actualFromMap(
        Map<String, dynamic>.from(raw),
        slotId: slotId,
      );
    }
    return parsed;
  }

  ExerciseActual _actualFromMap(
    Map<String, dynamic> data, {
    required String slotId,
  }) {
    return ExerciseActual(
      slotId: slotId,
      exerciseId: data['exerciseId'] as String? ?? '',
      mode: _parseExerciseMode(data['mode'] as String?),
      sets: data['sets'] as int?,
      reps: data['reps'] as String?,
      durationSeconds: data['durationSeconds'] as int?,
      weight: data['weight'] as String?,
      restSeconds: data['restSeconds'] as int?,
      notes: data['notes'] as String?,
    );
  }

  Future<Map<String, dynamic>> _prepareSlotResults({
    required String instanceId,
    required List<ExerciseActual> actuals,
  }) async {
    final instance = await getById(instanceId);
    if (instance == null) {
      throw StateError('Instance $instanceId not found');
    }
    final version = await WorkoutTemplateRepository(
      firestore: _firestore,
    ).getVersion(instance.workoutTemplateId, instance.workoutTemplateVersion);
    if (version == null) {
      throw StateError(
        'Workout ${instance.workoutTemplateId} version '
        '${instance.workoutTemplateVersion} not found',
      );
    }
    final slotsById = <String, ({ExerciseSlot slot, int slotOrder})>{
      for (var index = 0; index < version.exerciseSlots.length; index++)
        version.exerciseSlots[index].slotId: (
          slot: version.exerciseSlots[index],
          slotOrder: version.exerciseSlots[index].legacyStorageOrder ?? index,
        ),
    };
    final result = <String, dynamic>{};
    for (final actual in actuals) {
      actual.validate();
      var resolvedSlotId = actual.slotId;
      var pinned = slotsById[resolvedSlotId];
      if (!actual.hasExplicitSlotId) {
        final matchingSlots = slotsById.entries
            .where((entry) => entry.value.slot.exerciseId == actual.exerciseId)
            .toList();
        if (matchingSlots.length != 1) {
          throw StateError(
            matchingSlots.isEmpty
                ? 'Exercise ${actual.exerciseId} is not part of workout '
                    'instance $instanceId'
                : 'Exercise ${actual.exerciseId} occurs more than once; '
                    'a stable slot ID is required',
          );
        }
        resolvedSlotId = matchingSlots.single.key;
        pinned = matchingSlots.single.value;
      }
      if (pinned == null) {
        throw StateError(
          'Slot $resolvedSlotId is not part of workout instance $instanceId',
        );
      }
      if (pinned.slot.exerciseId != actual.exerciseId) {
        throw StateError(
          'Actual for slot $resolvedSlotId references the wrong exercise',
        );
      }
      if (result.containsKey(resolvedSlotId)) {
        throw ArgumentError('Only one actual is allowed per exercise slot');
      }
      result[resolvedSlotId] = {
        ..._actualToMap(actual),
        'slotOrder': pinned.slotOrder,
      };
    }
    return result;
  }

  Future<void> _writeCompletion({
    required String instanceId,
    required String athleteId,
    required WorkoutInstanceStatus requiredStatus,
    required Map<String, dynamic> actualsBySlot,
    required Map<String, dynamic> parentFields,
  }) async {
    final instanceRef = _collection.doc(instanceId);
    final storedResults = await instanceRef.collection('slotResults').get();
    final storedSlotIds = storedResults.docs.map((doc) => doc.id).toSet();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(instanceRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('Instance $instanceId not found');
      }
      final data = snapshot.data()!;
      if (data['athleteId'] != athleteId) {
        throw StateError('User $athleteId does not own instance $instanceId');
      }
      if (data['status'] != requiredStatus.name) {
        throw StateError('Instance $instanceId must be ${requiredStatus.name}');
      }

      final previousSlotIds =
          (data['actualSlotIds'] as List<dynamic>? ?? const [])
              .whereType<String>();
      for (final slotId in {...storedSlotIds, ...previousSlotIds}) {
        transaction.delete(instanceRef.collection('slotResults').doc(slotId));
      }
      for (final entry in actualsBySlot.entries) {
        transaction.set(
          instanceRef.collection('slotResults').doc(entry.key),
          entry.value as Map<String, dynamic>,
        );
      }
      transaction.update(instanceRef, {
        ...parentFields,
        'actualsStorageFormat': 'slotResultsSubcollection',
        'actualSlotIds': actualsBySlot.keys.toList(),
        'actualsBySlot': FieldValue.delete(),
        'actuals': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Migrates legacy list-based actuals to stable workout slot IDs.
  ///
  /// Repeated exercises are migrated only when every repeated occurrence has
  /// a result, so an ambiguous partial result is never guessed.
  Future<int> migrateLegacyActualsToSlotIds({
    required String instanceId,
    required String athleteId,
  }) async {
    final doc = await _collection.doc(instanceId).get();
    if (!doc.exists || doc.data() == null) {
      throw StateError('Instance $instanceId not found');
    }
    final data = doc.data()!;
    if (data['athleteId'] != athleteId) {
      throw StateError('User $athleteId does not own instance $instanceId');
    }
    final actualSlotIds = data['actualSlotIds'];
    final hasDeclaredSlotResults =
        data['actualsStorageFormat'] == 'slotResultsSubcollection' &&
            (actualSlotIds is! List || actualSlotIds.isNotEmpty);
    if (data['actualsBySlot'] is Map || hasDeclaredSlotResults) {
      return 0;
    }
    final legacy = data['actuals'];
    if (legacy is! List || legacy.isEmpty) return 0;

    final version =
        await WorkoutTemplateRepository(firestore: _firestore).getVersion(
      data['workoutTemplateId'] as String? ?? '',
      data['workoutTemplateVersion'] as int? ?? 1,
    );
    if (version == null) {
      throw StateError('Pinned workout version not found');
    }
    final slotsByExercise = <String, List<ExerciseSlot>>{};
    for (final slot in version.exerciseSlots) {
      slotsByExercise.putIfAbsent(slot.exerciseId, () => []).add(slot);
    }
    final actualMaps = <Map<String, dynamic>>[];
    for (final raw in legacy) {
      if (raw is! Map) {
        throw StateError('Legacy actual entries must be maps');
      }
      actualMaps.add(Map<String, dynamic>.from(raw));
    }
    final actualCountByExercise = <String, int>{};
    for (final actual in actualMaps) {
      final exerciseId = actual['exerciseId'] as String? ?? '';
      actualCountByExercise.update(
        exerciseId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    for (final entry in actualCountByExercise.entries) {
      final slotCount = slotsByExercise[entry.key]?.length ?? 0;
      if (slotCount == 0) {
        throw StateError('Legacy actual references an unknown exercise');
      }
      if (entry.value > slotCount) {
        throw StateError(
          'Legacy results exceed the available slots for ${entry.key}',
        );
      }
      if (slotCount > 1 && entry.value != slotCount) {
        throw StateError(
          'Legacy results for repeated exercise ${entry.key} are ambiguous',
        );
      }
    }

    final usedByExercise = <String, int>{};
    final migrated = <String, dynamic>{};
    for (final actualMap in actualMaps) {
      final exerciseId = actualMap['exerciseId'] as String? ?? '';
      final index = usedByExercise.update(
        exerciseId,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final slot = slotsByExercise[exerciseId]![index];
      final actual = _actualFromMap(actualMap, slotId: slot.slotId);
      migrated[slot.slotId] = {
        ..._actualToMap(actual),
        'slotOrder':
            slot.legacyStorageOrder ?? version.exerciseSlots.indexOf(slot),
      };
    }
    await _firestore.runTransaction((transaction) async {
      final latest = await transaction.get(doc.reference);
      if (!latest.exists || latest.data()?['athleteId'] != athleteId) {
        throw StateError('User $athleteId does not own instance $instanceId');
      }
      final latestData = latest.data()!;
      final latestSlotIds = latestData['actualSlotIds'];
      final latestHasDeclaredSlotResults =
          latestData['actualsStorageFormat'] == 'slotResultsSubcollection' &&
              (latestSlotIds is! List || latestSlotIds.isNotEmpty);
      if (latestData['actualsBySlot'] is Map || latestHasDeclaredSlotResults) {
        throw StateError('Workout actuals were already migrated');
      }
      for (final entry in migrated.entries) {
        transaction.set(
          doc.reference.collection('slotResults').doc(entry.key),
          entry.value as Map<String, dynamic>,
        );
      }
      transaction.update(doc.reference, {
        'actualsStorageFormat': 'slotResultsSubcollection',
        'actualSlotIds': migrated.keys.toList(),
        'actualsBySlot': FieldValue.delete(),
        'actuals': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return migrated.length;
  }

  Recurrence _recurrenceFromMap(Map<String, dynamic> data) {
    return Recurrence(
      pattern: _parseRecurrencePattern(data['pattern'] as String?),
      daysOfWeek:
          (data['daysOfWeek'] as List<dynamic>?)?.map((d) => d as int).toList(),
      intervalDays: data['intervalDays'] as int?,
      endDate: data['endDate'] as String? ?? '',
    );
  }

  static WorkoutInstanceStatus _parseStatus(String? value) {
    if (value == null) return WorkoutInstanceStatus.scheduled;
    return WorkoutInstanceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WorkoutInstanceStatus.scheduled,
    );
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

  static RecurrencePattern _parseRecurrencePattern(String? value) {
    if (value == null) return RecurrencePattern.weekly;
    return RecurrencePattern.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RecurrencePattern.weekly,
    );
  }

  static ProgramRelationshipMode? _parseRelationshipMode(String? value) {
    if (value == null) return null;
    return ProgramRelationshipMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ProgramRelationshipMode.copied,
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Result of an [WorkoutInstanceRepository.assignProgram] call.
class ProgramAssignmentResult {
  const ProgramAssignmentResult({
    required this.programInstanceId,
    required this.instanceCount,
  });

  /// First-class athlete program instance created by the assignment.
  final String programInstanceId;

  /// Legacy compatibility alias.
  String get assignmentId => programInstanceId;

  /// Number of workout instances materialized.
  final int instanceCount;
}
