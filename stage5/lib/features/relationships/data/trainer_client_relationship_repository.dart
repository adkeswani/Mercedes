import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/relationships/domain/trainer_client_relationship.dart';

/// Firestore repository for durable trainer-client relationships.
class TrainerClientRelationshipRepository {
  TrainerClientRelationshipRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('trainerClientRelationships');

  static String relationshipId(String trainerId, String athleteId) =>
      '${trainerId}_$athleteId';

  void _verifyTrainerCaller(String trainerId, String callerUserId) {
    if (trainerId != callerUserId) {
      throw StateError(
        'User $callerUserId is not the owner of trainer roster $trainerId',
      );
    }
  }

  Map<String, dynamic> _activeRelationshipData({
    required String trainerId,
    required String athleteId,
    required String callerUserId,
  }) {
    return {
      'trainerId': trainerId,
      'athleteId': athleteId,
      'status': TrainerClientRelationshipStatus.active.name,
      'startedAt': FieldValue.serverTimestamp(),
      'endedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': callerUserId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': callerUserId,
      'deletedAt': null,
      'deletedBy': null,
    };
  }

  /// Starts a relationship, or reactivates a previously ended relationship.
  Future<String> startRelationship({
    required String trainerId,
    required String athleteId,
    required String callerUserId,
  }) async {
    _verifyTrainerCaller(trainerId, callerUserId);
    if (athleteId.isEmpty) {
      throw ArgumentError('athleteId cannot be empty');
    }
    if (trainerId == athleteId) {
      throw ArgumentError('A trainer-client relationship cannot be self-owned');
    }

    final id = relationshipId(trainerId, athleteId);
    final docRef = _collection.doc(id);
    await _firestore.runTransaction<void>((transaction) async {
      final existing = await transaction.get(docRef);
      if (!existing.exists) {
        transaction.set(
          docRef,
          _activeRelationshipData(
            trainerId: trainerId,
            athleteId: athleteId,
            callerUserId: callerUserId,
          ),
        );
        return;
      }

      final data = existing.data()!;
      if (data['trainerId'] != callerUserId || data['athleteId'] != athleteId) {
        throw StateError('Relationship $id is not owned by $callerUserId');
      }
      if (data['status'] == TrainerClientRelationshipStatus.active.name) {
        throw StateError('Relationship $id is already active');
      }
      if (data['status'] == TrainerClientRelationshipStatus.ending.name) {
        throw StateError('Relationship $id is still ending');
      }
      transaction.update(docRef, {
        'status': TrainerClientRelationshipStatus.active.name,
        'startedAt': FieldValue.serverTimestamp(),
        'endedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': callerUserId,
      });
    });
    return id;
  }

  /// Creates missing roster relationships inferred from active legacy
  /// enrollments owned by [trainerId].
  ///
  /// Existing relationships are left unchanged, including ended relationships,
  /// so an explicit removal is never undone by a later migration run. Personal
  /// self-enrollments are not trainer-client relationships.
  Future<int> backfillActiveEnrollmentRelationships({
    required String trainerId,
    required String callerUserId,
  }) async {
    _verifyTrainerCaller(trainerId, callerUserId);

    final enrollments = await _firestore
        .collection('enrollments')
        .where('addedBy', isEqualTo: trainerId)
        .where('status', isEqualTo: EnrollmentStatus.active.name)
        .get();

    var count = 0;
    for (final enrollment in enrollments.docs) {
      final enrollmentData = enrollment.data();
      final athleteId = enrollmentData['athleteId'] as String?;
      final programId = enrollmentData['programId'] as String?;
      if (athleteId == null || athleteId.isEmpty) {
        throw StateError('Enrollment ${enrollment.id} has no athlete');
      }
      if (programId == null || programId.isEmpty) {
        throw StateError('Enrollment ${enrollment.id} has no program');
      }
      if (athleteId == trainerId) {
        continue;
      }

      final relationshipRef = _collection.doc(
        relationshipId(trainerId, athleteId),
      );
      final enrollmentRef =
          _firestore.collection('enrollments').doc(enrollment.id);

      final created = await _firestore.runTransaction<bool>((
        transaction,
      ) async {
        final existingRelationship = await transaction.get(relationshipRef);
        if (existingRelationship.exists) {
          final data = existingRelationship.data()!;
          if (data['trainerId'] != trainerId ||
              data['athleteId'] != athleteId) {
            throw StateError(
              'Relationship ${relationshipRef.id} is not owned by $trainerId',
            );
          }
          return false;
        }

        final currentEnrollment = await transaction.get(enrollmentRef);
        if (!currentEnrollment.exists) {
          return false;
        }
        final currentData = currentEnrollment.data()!;
        if (currentData['status'] != EnrollmentStatus.active.name) {
          return false;
        }
        if (currentData['addedBy'] != trainerId ||
            currentData['athleteId'] != athleteId ||
            currentData['programId'] != programId) {
          throw StateError(
            'Enrollment ${enrollment.id} is not owned by $trainerId',
          );
        }

        transaction.set(
          relationshipRef,
          _activeRelationshipData(
            trainerId: trainerId,
            athleteId: athleteId,
            callerUserId: callerUserId,
          ),
        );
        return true;
      });
      if (created) {
        count++;
      }
    }
    return count;
  }

  /// Ends an active relationship without deleting its audit history.
  Future<void> endRelationship({
    required String trainerId,
    required String athleteId,
    required String callerUserId,
  }) async {
    _verifyTrainerCaller(trainerId, callerUserId);
    final id = relationshipId(trainerId, athleteId);
    final docRef = _collection.doc(id);
    final existing = await docRef.get();
    if (!existing.exists) {
      throw StateError('Relationship $id not found');
    }
    final data = existing.data()!;
    if (data['trainerId'] != callerUserId || data['athleteId'] != athleteId) {
      throw StateError('Relationship $id is not owned by $callerUserId');
    }
    final status = data['status'] as String?;
    if (status == TrainerClientRelationshipStatus.ended.name) {
      return;
    }
    if (status != TrainerClientRelationshipStatus.active.name &&
        status != TrainerClientRelationshipStatus.ending.name) {
      throw StateError('Relationship $id has an invalid lifecycle status');
    }

    // Enter `ending` first so new assignments are blocked while the
    // idempotent unlink batches remain readable and recoverable.
    if (status == TrainerClientRelationshipStatus.active.name) {
      await docRef.update({
        'status': TrainerClientRelationshipStatus.ending.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': callerUserId,
      });
    }

    final subscriptions = await _firestore
        .collection('athleteProgramInstances')
        .where('assigningTrainerId', isEqualTo: trainerId)
        .where('athleteOwnerId', isEqualTo: athleteId)
        .where(
          'relationshipMode',
          isEqualTo: ProgramRelationshipMode.subscribed.name,
        )
        .get();
    for (var start = 0; start < subscriptions.docs.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, subscriptions.docs.length);
      for (final subscription in subscriptions.docs.sublist(start, end)) {
        final instance = subscription.data();
        if (instance['assigningTrainerId'] != callerUserId ||
            instance['athleteOwnerId'] != athleteId) {
          throw StateError(
            'Program instance ${subscription.id} relationship mismatch',
          );
        }
        await _syncWorkoutRelationshipModes(
          subscription.id,
          trainerId,
          athleteId,
        );
        batch.update(subscription.reference, {
          'relationshipMode': ProgramRelationshipMode.copied.name,
          'unlinkedAt': FieldValue.serverTimestamp(),
          'unlinkReason': 'relationshipEnded',
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': callerUserId,
        });
      }

      await batch.commit();
    }
    await docRef.update({
      'status': TrainerClientRelationshipStatus.ended.name,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': callerUserId,
    });
  }

  Future<void> _syncWorkoutRelationshipModes(
    String programInstanceId,
    String trainerId,
    String athleteId,
  ) async {
    final workouts = await _firestore
        .collection('workoutInstances')
        .where('athleteProgramInstanceId', isEqualTo: programInstanceId)
        .where('athleteId', isEqualTo: athleteId)
        .where('programOwnerId', isEqualTo: trainerId)
        .get();
    final now = DateTime.now().toUtc();
    final today = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final mutable = workouts.docs.where((workout) {
      final data = workout.data();
      return data['status'] == 'scheduled' &&
          (data['scheduledDate'] as String? ?? '').compareTo(today) >= 0 &&
          data['relationshipMode'] == ProgramRelationshipMode.subscribed.name;
    }).toList();
    for (var start = 0; start < mutable.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, mutable.length);
      for (final workout in mutable.sublist(start, end)) {
        batch.update(workout.reference, {
          'relationshipMode': ProgramRelationshipMode.copied.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  /// Resumes any interrupted unlink workflows owned by [trainerId].
  Future<int> recoverEndingRelationships({
    required String trainerId,
    required String callerUserId,
  }) async {
    _verifyTrainerCaller(trainerId, callerUserId);
    final ending = await _collection
        .where('trainerId', isEqualTo: trainerId)
        .where(
          'status',
          isEqualTo: TrainerClientRelationshipStatus.ending.name,
        )
        .get();
    for (final relationship in ending.docs) {
      final data = relationship.data();
      final athleteId = data['athleteId'] as String?;
      if (data['trainerId'] != trainerId ||
          athleteId == null ||
          athleteId.isEmpty) {
        throw StateError(
          'Relationship ${relationship.id} is not owned by $trainerId',
        );
      }
      await endRelationship(
        trainerId: trainerId,
        athleteId: athleteId,
        callerUserId: callerUserId,
      );
    }
    return ending.docs.length;
  }

  Stream<List<TrainerClientRelationship>> watchClients(String trainerId) {
    return _collection
        .where('trainerId', isEqualTo: trainerId)
        .where('status', isEqualTo: TrainerClientRelationshipStatus.active.name)
        .snapshots()
        .map((snapshot) {
      final relationships =
          snapshot.docs.map((doc) => _fromMap(doc.data(), doc.id)).toList();
      relationships.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return relationships;
    });
  }

  Stream<List<TrainerClientRelationship>> watchTrainers(String athleteId) {
    return _collection
        .where('athleteId', isEqualTo: athleteId)
        .where('status', isEqualTo: TrainerClientRelationshipStatus.active.name)
        .snapshots()
        .map((snapshot) {
      final relationships =
          snapshot.docs.map((doc) => _fromMap(doc.data(), doc.id)).toList();
      relationships.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return relationships;
    });
  }

  Future<TrainerClientRelationship?> getRelationship(
    String trainerId,
    String athleteId,
  ) async {
    final doc =
        await _collection.doc(relationshipId(trainerId, athleteId)).get();
    if (!doc.exists || doc.data() == null) return null;
    return _fromMap(doc.data()!, doc.id);
  }

  Future<bool> isActive(String trainerId, String athleteId) async {
    final relationship = await getRelationship(trainerId, athleteId);
    return relationship?.isActive ?? false;
  }

  TrainerClientRelationship _fromMap(Map<String, dynamic> data, String id) {
    return TrainerClientRelationship(
      id: id,
      trainerId: data['trainerId'] as String? ?? '',
      athleteId: data['athleteId'] as String? ?? '',
      status: _parseStatus(data['status'] as String?),
      startedAt: _toDateTime(data['startedAt']),
      endedAt: data['endedAt'] == null ? null : _toDateTime(data['endedAt']),
      createdAt: _toDateTime(data['createdAt']),
      createdBy: data['createdBy'] as String? ?? '',
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String? ?? '',
      deletedAt:
          data['deletedAt'] == null ? null : _toDateTime(data['deletedAt']),
      deletedBy: data['deletedBy'] as String?,
    );
  }

  static TrainerClientRelationshipStatus _parseStatus(String? value) {
    return TrainerClientRelationshipStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TrainerClientRelationshipStatus.ended,
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
