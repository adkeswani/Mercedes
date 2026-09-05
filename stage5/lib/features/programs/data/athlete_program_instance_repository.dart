import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';

/// Firestore persistence and lifecycle operations for athlete-owned programs.
class AthleteProgramInstanceRepository {
  AthleteProgramInstanceRepository({
    FirebaseFirestore? firestore,
    DateTime Function()? now,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _now = now ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('athleteProgramInstances');

  Future<AthleteProgramInstance?> getById(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return _fromMap(doc.data()!, doc.id);
  }

  Stream<List<AthleteProgramInstance>> watchForAthlete(String athleteId) {
    return _collection
        .where('athleteOwnerId', isEqualTo: athleteId)
        .orderBy('startDate', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => _fromMap(doc.data(), doc.id)).toList(),
        );
  }

  Stream<List<AthleteProgramInstance>> watchForTrainer(
    String trainerId,
    Iterable<String> activeAthleteIds,
  ) {
    final athleteIds = activeAthleteIds.toSet().toList()..sort();
    if (athleteIds.isEmpty) {
      return Stream.value(const []);
    }

    late StreamController<List<AthleteProgramInstance>> controller;
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final values = <String, List<AthleteProgramInstance>>{};

    void emit() {
      if (values.length != athleteIds.length) return;
      final combined = values.values.expand((items) => items).toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));
      controller.add(combined);
    }

    controller = StreamController<List<AthleteProgramInstance>>(
      onListen: () {
        for (final athleteId in athleteIds) {
          final subscription = _collection
              .where('assigningTrainerId', isEqualTo: trainerId)
              .where('athleteOwnerId', isEqualTo: athleteId)
              .where(
                'status',
                isEqualTo: AthleteProgramInstanceStatus.active.name,
              )
              .snapshots()
              .listen(
            (snapshot) {
              values[athleteId] = snapshot.docs
                  .map((doc) => _fromMap(doc.data(), doc.id))
                  .toList();
              emit();
            },
            onError: controller.addError,
          );
          subscriptions.add(subscription);
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

  /// Converts a linked subscription before an athlete makes a structural edit.
  ///
  /// UI callers must obtain confirmation and pass [confirmed] explicitly.
  Future<void> convertSubscriptionToCopy({
    required String instanceId,
    required String athleteId,
    required bool confirmed,
    String reason = 'structuralCustomization',
  }) async {
    if (!confirmed) {
      throw StateError('Structural customization requires confirmation');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('reason cannot be empty');
    }
    final ref = _collection.doc(instanceId);
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw StateError('Athlete program instance $instanceId not found');
    }
    final data = snapshot.data()!;
    if (data['athleteOwnerId'] != athleteId) {
      throw StateError(
        'User $athleteId does not own athlete program instance $instanceId',
      );
    }
    if (data['status'] != AthleteProgramInstanceStatus.active.name) {
      throw StateError('Only active program instances can be customized');
    }
    if (data['relationshipMode'] != ProgramRelationshipMode.subscribed.name ||
        data['unlinkedAt'] != null) {
      throw StateError('Program instance $instanceId is not subscribed');
    }

    final workouts = await _firestore
        .collection('workoutInstances')
        .where('athleteProgramInstanceId', isEqualTo: instanceId)
        .where('athleteId', isEqualTo: athleteId)
        .get();
    final now = _now().toUtc();
    final today = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final mutableWorkouts = workouts.docs
        .where(
          (doc) =>
              doc.data()['status'] == WorkoutInstanceStatus.scheduled.name &&
              (doc.data()['scheduledDate'] as String? ?? '').compareTo(
                    today,
                  ) >=
                  0,
        )
        .toList();
    if (mutableWorkouts.length > 498) {
      throw StateError(
        'Program instance has too many workouts to convert atomically',
      );
    }
    final batch = _firestore.batch();
    batch.update(ref, {
      'relationshipMode': ProgramRelationshipMode.copied.name,
      'unlinkedAt': FieldValue.serverTimestamp(),
      'unlinkReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': athleteId,
    });
    for (final workout in mutableWorkouts) {
      batch.update(workout.reference, {
        'relationshipMode': ProgramRelationshipMode.copied.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Backfills first-class records for legacy `programAssignmentId` groups.
  ///
  /// Legacy groups are conservatively treated as independent copies. The
  /// athlete must perform the migration because the resulting record is owned
  /// by that athlete.
  Future<int> backfillLegacyAssignments({
    required String athleteId,
    required String actorId,
  }) async {
    if (athleteId != actorId) {
      throw StateError('Only the athlete can migrate their program instances');
    }
    final workouts = await _firestore
        .collection('workoutInstances')
        .where('athleteId', isEqualTo: athleteId)
        .get();
    final groups =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final workout in workouts.docs) {
      final data = workout.data();
      final assignmentId = data['programAssignmentId'] as String?;
      if (assignmentId == null || assignmentId.isEmpty) {
        continue;
      }
      final firstClassId = data['athleteProgramInstanceId'] as String?;
      if (firstClassId != null && firstClassId != assignmentId) {
        throw StateError(
          'Workout ${workout.id} has conflicting program instance IDs',
        );
      }
      groups.putIfAbsent(assignmentId, () => []).add(workout);
    }

    var created = 0;
    for (final entry in groups.entries) {
      final instanceRef = _collection.doc(entry.key);
      final existing = await instanceRef.get();
      if (existing.exists) {
        await _backfillWorkoutReferences(entry.key, entry.value);
        continue;
      }
      final first = entry.value.first.data();
      if (first['athleteId'] != actorId) {
        throw StateError('Legacy assignment ${entry.key} ownership mismatch');
      }
      final dates = entry.value
          .map((doc) => doc.data()['scheduledDate'] as String? ?? '')
          .where((date) => date.isNotEmpty)
          .toList()
        ..sort();
      if (dates.isEmpty) {
        throw StateError('Legacy assignment ${entry.key} has no schedule');
      }
      final trainerId = first['programOwnerId'] as String? ??
          first['assignedBy'] as String? ??
          '';
      final programId = first['programId'] as String? ?? '';
      final programVersion = (first['programVersion'] as int?) ?? 0;
      if (trainerId.isEmpty || programId.isEmpty || programVersion < 1) {
        throw StateError(
          'Legacy assignment ${entry.key} lacks safe source metadata',
        );
      }
      final statuses = entry.value
          .map((doc) => doc.data()['status'] as String? ?? '')
          .toList();
      final allTerminal = statuses.every(
        (status) =>
            status == WorkoutInstanceStatus.completed.name ||
            status == WorkoutInstanceStatus.missed.name ||
            status == WorkoutInstanceStatus.cancelled.name,
      );
      final allCancelled = statuses.every(
        (status) => status == WorkoutInstanceStatus.cancelled.name,
      );
      final lifecycleStatus = allCancelled
          ? AthleteProgramInstanceStatus.cancelled
          : allTerminal
              ? AthleteProgramInstanceStatus.completed
              : AthleteProgramInstanceStatus.active;
      final batch = _firestore.batch();
      batch.set(instanceRef, {
        'athleteOwnerId': athleteId,
        'assigningTrainerId': trainerId,
        'sourceProgramId': programId,
        'sourceProgramVersion': programVersion,
        'relationshipMode': ProgramRelationshipMode.copied.name,
        'startDate': dates.first,
        'expectedEndDate': dates.last,
        'workoutCount': entry.value.length,
        'status': lifecycleStatus.name,
        'linkedAt': null,
        'unlinkedAt': null,
        'unlinkReason': null,
        'materializationKey': null,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': actorId,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': actorId,
        'deletedAt': null,
        'deletedBy': null,
      });
      for (final workout in entry.value.take(499)) {
        batch.update(workout.reference, {
          'athleteProgramInstanceId': entry.key,
          'relationshipMode': ProgramRelationshipMode.copied.name,
        });
      }
      await batch.commit();
      if (entry.value.length > 499) {
        await _backfillWorkoutReferences(entry.key, entry.value);
      }
      created++;
    }
    return created;
  }

  Future<void> _backfillWorkoutReferences(
    String instanceId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> workouts,
  ) async {
    final missing = workouts
        .where((doc) => doc.data()['athleteProgramInstanceId'] == null)
        .toList();
    if (missing.isEmpty) {
      return;
    }
    for (var start = 0; start < missing.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, missing.length);
      for (final workout in missing.sublist(start, end)) {
        batch.update(workout.reference, {
          'athleteProgramInstanceId': instanceId,
          'relationshipMode': ProgramRelationshipMode.copied.name,
        });
      }
      await batch.commit();
    }
  }

  AthleteProgramInstance _fromMap(Map<String, dynamic> data, String id) {
    return AthleteProgramInstance(
      id: id,
      athleteOwnerId: data['athleteOwnerId'] as String? ?? '',
      assigningTrainerId: data['assigningTrainerId'] as String? ?? '',
      sourceProgramId: data['sourceProgramId'] as String? ?? '',
      sourceProgramVersion: (data['sourceProgramVersion'] as int?) ?? 0,
      relationshipMode: _parseMode(data['relationshipMode'] as String?),
      startDate: data['startDate'] as String? ?? '',
      expectedEndDate: data['expectedEndDate'] as String? ?? '',
      workoutCount: (data['workoutCount'] as int?) ?? 0,
      status: _parseStatus(data['status'] as String?),
      linkedAt: data['linkedAt'] == null ? null : _toDateTime(data['linkedAt']),
      unlinkedAt:
          data['unlinkedAt'] == null ? null : _toDateTime(data['unlinkedAt']),
      unlinkReason: data['unlinkReason'] as String?,
      materializationKey: data['materializationKey'] as String?,
      createdAt: _toDateTime(data['createdAt']),
      createdBy: data['createdBy'] as String? ?? '',
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String? ?? '',
      deletedAt:
          data['deletedAt'] == null ? null : _toDateTime(data['deletedAt']),
      deletedBy: data['deletedBy'] as String?,
    );
  }

  static ProgramRelationshipMode _parseMode(String? value) {
    return ProgramRelationshipMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ProgramRelationshipMode.copied,
    );
  }

  static AthleteProgramInstanceStatus _parseStatus(String? value) {
    return AthleteProgramInstanceStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => AthleteProgramInstanceStatus.active,
    );
  }

  static DateTime _toDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
