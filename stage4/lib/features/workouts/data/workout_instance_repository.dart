import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/programs/data/enrollment_repository.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';

/// Firestore repository for workout instance management.
///
/// Targets the `workoutInstances/{instanceId}` collection.
/// Handles scheduling, completion, cancellation, and calendar queries.
class WorkoutInstanceRepository {
  WorkoutInstanceRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('workoutInstances');

  /// Verifies the caller can assign workouts in this program.
  ///
  /// For assignable programs: caller must be the owner and athlete
  /// must be actively enrolled. For personal programs: caller must
  /// be both the owner and the athlete (self-assignment).
  /// Throws [StateError] on any violation.
  Future<void> _verifyCanAssign({
    required String programId,
    required String athleteId,
    required String assignedBy,
  }) async {
    final programDoc = await _firestore
        .collection('programs')
        .doc(programId)
        .get();
    if (!programDoc.exists) {
      throw StateError('Program $programId not found');
    }
    final data = programDoc.data()!;
    final ownerId = data['ownerId'] as String?;
    final type = data['type'] as String?;

    if (ownerId != assignedBy) {
      throw StateError(
        'User $assignedBy is not the owner of program $programId',
      );
    }

    if (type == 'personal') {
      if (athleteId != assignedBy) {
        throw StateError(
          'Personal programs only allow self-assignment',
        );
      }
    } else {
      // Assignable — athlete must be enrolled
      final enrollmentDoc = await _firestore
          .collection('enrollments')
          .doc('${programId}_$athleteId')
          .get();
      if (!enrollmentDoc.exists ||
          enrollmentDoc.data()?['status'] != 'active') {
        throw StateError(
          'Athlete $athleteId is not actively enrolled in program $programId',
        );
      }
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
    await _verifyCanAssign(
      programId: programId,
      athleteId: athleteId,
      assignedBy: assignedBy,
    );
    final docRef = _collection.doc();
    await docRef.set({
      'programId': programId,
      'programVersion': 0,
      'programAssignmentId': null,
      'athleteId': athleteId,
      'workoutTemplateId': workoutTemplateId,
      'workoutTemplateVersion': workoutTemplateVersion,
      'scheduledDate': scheduledDate,
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
      'actuals': [],
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

    await _verifyCanAssign(
      programId: programId,
      athleteId: athleteId,
      assignedBy: assignedBy,
    );

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
      'programVersion': 0,
      'programAssignmentId': null,
      'athleteId': athleteId,
      'workoutTemplateId': workoutTemplateId,
      'workoutTemplateVersion': workoutTemplateVersion,
      'scheduledDate': dates[0],
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
      'actuals': [],
      'athleteNotes': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Create child instances (remaining dates)
    for (var i = 1; i < dates.length; i++) {
      final childRef = _collection.doc();
      batch.set(childRef, {
        'programId': programId,
        'programVersion': 0,
        'programAssignmentId': null,
        'athleteId': athleteId,
        'workoutTemplateId': workoutTemplateId,
        'workoutTemplateVersion': workoutTemplateVersion,
        'scheduledDate': dates[i],
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
        'actuals': [],
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
  }) async {
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(startDate)) {
      throw ArgumentError(
        'startDate must be ISO 8601 date format (YYYY-MM-DD)',
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
      throw StateError(
        'Program $programId has no published version to assign',
      );
    }

    if (type == ProgramType.personal.name) {
      if (athleteId != assignedBy) {
        throw StateError('Personal programs only allow self-assignment');
      }
    } else {
      // Assignable — auto-enroll the athlete if needed.
      final enrollmentRepo = EnrollmentRepository(firestore: _firestore);
      final enrolled = await enrollmentRepo.isEnrolled(programId, athleteId);
      if (!enrolled) {
        await enrollmentRepo.enrollAthlete(
          programId: programId,
          athleteId: athleteId,
          addedBy: assignedBy,
        );
      }
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

    // Resolve each referenced workout template's type for load metrics.
    final templateIds = <String>{
      for (final e in entries)
        (e as Map<String, dynamic>)['workoutTemplateId'] as String? ?? '',
    }..removeWhere((id) => id.isEmpty);
    final typeByTemplate = <String, WorkoutType>{};
    await Future.wait(templateIds.map((tid) async {
      final tDoc =
          await _firestore.collection('workoutTemplates').doc(tid).get();
      typeByTemplate[tid] =
          _parseWorkoutType(tDoc.data()?['workoutType'] as String?);
    }));

    final assignmentId = _collection.doc().id;
    final batch = _firestore.batch();

    for (final raw in entries) {
      final entry = raw as Map<String, dynamic>;
      final templateId = entry['workoutTemplateId'] as String? ?? '';
      final templateVersion = (entry['workoutTemplateVersion'] as int?) ?? 1;
      final dayOffset = (entry['dayOffset'] as int?) ?? 0;
      final scheduledDate = addDays(startDate, dayOffset);
      final workoutType = typeByTemplate[templateId] ?? WorkoutType.fullBody;

      final docRef = _collection.doc();
      batch.set(docRef, {
        'programId': programId,
        'programVersion': currentVersion,
        'programAssignmentId': assignmentId,
        'athleteId': athleteId,
        'workoutTemplateId': templateId,
        'workoutTemplateVersion': templateVersion,
        'scheduledDate': scheduledDate,
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
        'actuals': [],
        'athleteNotes': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return ProgramAssignmentResult(
      assignmentId: assignmentId,
      instanceCount: entries.length,
    );
  }

  /// Cancels all still-scheduled instances belonging to a program assignment.
  ///
  /// Completed and missed instances are preserved. Returns the number of
  /// instances cancelled.
  Future<int> cancelProgramAssignment({
    required String programAssignmentId,
  }) async {
    final snapshot = await _collection
        .where('programAssignmentId', isEqualTo: programAssignmentId)
        .where('status', isEqualTo: WorkoutInstanceStatus.scheduled.name)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'status': WorkoutInstanceStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (snapshot.docs.isNotEmpty) await batch.commit();
    return snapshot.docs.length;
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
    final snapshot = await _collection
        .where('programAssignmentId', isEqualTo: programAssignmentId)
        .where('assignedBy', isEqualTo: ownerId)
        .get();

    final targets = snapshot.docs
        .where((d) =>
            d.data()['status'] != WorkoutInstanceStatus.completed.name)
        .toList();
    final batch = _firestore.batch();
    for (final doc in targets) {
      batch.delete(doc.reference);
    }
    if (targets.isNotEmpty) await batch.commit();
    return targets.length;
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
    if (instance.assignedBy != ownerId && instance.athleteId != ownerId) {
      throw StateError('User $ownerId did not assign instance $instanceId');
    }
    await _collection.doc(instanceId).delete();
  }

  /// Cancels all future scheduled instances in a recurrence group.
  ///
  /// Finds all instances with the given [recurrenceRootId] (or the root
  /// itself) that are still scheduled, and cancels them.
  Future<int> cancelRecurrence({
    required String recurrenceRootId,
  }) async {
    // Cancel children
    final childSnapshot = await _collection
        .where('recurrenceRootId', isEqualTo: recurrenceRootId)
        .where('status', isEqualTo: WorkoutInstanceStatus.scheduled.name)
        .get();

    // Also check the root itself
    final rootDoc = await _collection.doc(recurrenceRootId).get();

    final batch = _firestore.batch();
    var count = 0;

    for (final doc in childSnapshot.docs) {
      batch.update(doc.reference, {
        'status': WorkoutInstanceStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      count++;
    }

    if (rootDoc.exists &&
        rootDoc.data()?['status'] == WorkoutInstanceStatus.scheduled.name) {
      batch.update(rootDoc.reference, {
        'status': WorkoutInstanceStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      count++;
    }

    if (count > 0) await batch.commit();
    return count;
  }

  /// Marks a workout instance as completed by the athlete.
  ///
  /// Sets status to `completed`, writes `completedAt`, and records
  /// RPE, duration, and per-exercise actuals.
  Future<void> completeWorkout({
    required String instanceId,
    required int rpe,
    required int durationMinutes,
    required List<ExerciseActual> actuals,
    double? loadPoints,
    String? loadStrategyId,
    String? athleteNotes,
  }) async {
    await _collection.doc(instanceId).update({
      'status': WorkoutInstanceStatus.completed.name,
      'completedAt': FieldValue.serverTimestamp(),
      'rpe': rpe,
      'durationMinutes': durationMinutes,
      'loadPoints': loadPoints,
      'loadStrategyId': loadStrategyId,
      'athleteNotes': athleteNotes,
      'actuals': actuals.map(_actualToMap).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Updates completion data on an already-completed workout instance.
  ///
  /// Allows the athlete or program owner to revise RPE, duration, notes,
  /// and per-exercise actuals after initial completion.
  Future<void> updateCompletion({
    required String instanceId,
    required int rpe,
    required int durationMinutes,
    required List<ExerciseActual> actuals,
    double? loadPoints,
    String? loadStrategyId,
    String? athleteNotes,
  }) async {
    await _collection.doc(instanceId).update({
      'rpe': rpe,
      'durationMinutes': durationMinutes,
      'loadPoints': loadPoints,
      'loadStrategyId': loadStrategyId,
      'athleteNotes': athleteNotes,
      'actuals': actuals.map(_actualToMap).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cancels all future scheduled workout instances for a program-athlete pair.
  ///
  /// Used when an athlete is removed from a program. Only cancels instances
  /// with status `scheduled` — completed and missed instances are preserved.
  Future<int> cancelFutureInstances({
    required String programId,
    required String athleteId,
  }) async {
    final snapshot = await _collection
        .where('programId', isEqualTo: programId)
        .where('athleteId', isEqualTo: athleteId)
        .where('status', isEqualTo: WorkoutInstanceStatus.scheduled.name)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'status': WorkoutInstanceStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return snapshot.docs.length;
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
        .map((snapshot) => snapshot.docs
            .map((doc) => _fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Streams workout instances for a specific program-athlete pair.
  ///
  /// Used by the owner to view an athlete's schedule within a program.
  Stream<List<WorkoutInstance>> watchProgramSchedule({
    required String programId,
    required String athleteId,
  }) {
    return _collection
        .where('programId', isEqualTo: programId)
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('scheduledDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Streams all instances the [ownerId] has assigned to [athleteId] across
  /// all of the owner's programs, within a date range.
  ///
  /// Used by the per-athlete trainer calendar so a coach can see every
  /// workout they've scheduled for an athlete, regardless of program.
  /// Requires a composite index on (assignedBy, athleteId, scheduledDate).
  Stream<List<WorkoutInstance>> watchAthleteCalendar({
    required String ownerId,
    required String athleteId,
    required String startDate,
    required String endDate,
  }) {
    return _collection
        .where('assignedBy', isEqualTo: ownerId)
        .where('athleteId', isEqualTo: athleteId)
        .where('scheduledDate', isGreaterThanOrEqualTo: startDate)
        .where('scheduledDate', isLessThanOrEqualTo: endDate)
        .orderBy('scheduledDate')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _fromMap(doc.data(), doc.id))
            .toList());
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
    final instance = await getById(instanceId);
    if (instance == null) {
      throw StateError('Instance $instanceId not found');
    }
    if (instance.assignedBy != ownerId) {
      throw StateError('User $ownerId did not assign instance $instanceId');
    }
    if (instance.status != WorkoutInstanceStatus.scheduled) {
      throw StateError('Only scheduled instances can be rescheduled');
    }
    await _collection.doc(instanceId).update({
      'scheduledDate': newDate,
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
    if (instance.assignedBy != ownerId) {
      throw StateError('User $ownerId did not assign instance $instanceId');
    }
    if (instance.status != WorkoutInstanceStatus.scheduled) {
      throw StateError('Only scheduled instances can be cancelled');
    }
    await _collection.doc(instanceId).update({
      'status': WorkoutInstanceStatus.cancelled.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Returns a single workout instance by ID, or null.
  Future<WorkoutInstance?> getById(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return _fromMap(doc.data()!, doc.id);
  }

  // -- Serialization helpers --

  WorkoutInstance _fromMap(Map<String, dynamic> data, String id) {
    return WorkoutInstance(
      id: id,
      programId: data['programId'] as String? ?? '',
      programVersion: (data['programVersion'] as int?) ?? 0,
      programAssignmentId: data['programAssignmentId'] as String?,
      athleteId: data['athleteId'] as String? ?? '',
      workoutTemplateId: data['workoutTemplateId'] as String? ?? '',
      workoutTemplateVersion:
          (data['workoutTemplateVersion'] as int?) ?? 1,
      scheduledDate: data['scheduledDate'] as String? ?? '',
      assignedBy: data['assignedBy'] as String? ?? '',
      assignedAt: _toDateTime(data['assignedAt']),
      status: _parseStatus(data['status'] as String?),
      completedAt: data['completedAt'] != null
          ? _toDateTime(data['completedAt'])
          : null,
      missedAt:
          data['missedAt'] != null ? _toDateTime(data['missedAt']) : null,
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
      actuals: _parseActuals(data['actuals']),
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

  List<ExerciseActual> _parseActuals(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];
    return data
        .map((item) => _actualFromMap(item as Map<String, dynamic>))
        .toList();
  }

  ExerciseActual _actualFromMap(Map<String, dynamic> data) {
    return ExerciseActual(
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

  Recurrence _recurrenceFromMap(Map<String, dynamic> data) {
    return Recurrence(
      pattern: _parseRecurrencePattern(data['pattern'] as String?),
      daysOfWeek: (data['daysOfWeek'] as List<dynamic>?)
          ?.map((d) => d as int)
          .toList(),
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

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Result of an [WorkoutInstanceRepository.assignProgram] call.
class ProgramAssignmentResult {
  const ProgramAssignmentResult({
    required this.assignmentId,
    required this.instanceCount,
  });

  /// Shared id tagging every instance created by this assignment.
  final String assignmentId;

  /// Number of workout instances materialized.
  final int instanceCount;
}
