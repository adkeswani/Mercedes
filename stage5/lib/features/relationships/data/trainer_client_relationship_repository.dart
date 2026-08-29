import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/relationships/domain/trainer_client_relationship.dart';

/// Firestore repository for durable trainer-client relationships.
class TrainerClientRelationshipRepository {
  TrainerClientRelationshipRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

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
        transaction.set(docRef, {
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
        });
        return;
      }

      final data = existing.data()!;
      if (data['trainerId'] != callerUserId || data['athleteId'] != athleteId) {
        throw StateError('Relationship $id is not owned by $callerUserId');
      }
      if (data['status'] == TrainerClientRelationshipStatus.active.name) {
        throw StateError('Relationship $id is already active');
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

  /// Ends an active relationship without deleting its audit history.
  Future<void> endRelationship({
    required String trainerId,
    required String athleteId,
    required String callerUserId,
  }) async {
    _verifyTrainerCaller(trainerId, callerUserId);
    final id = relationshipId(trainerId, athleteId);
    final docRef = _collection.doc(id);
    await _firestore.runTransaction<void>((transaction) async {
      final existing = await transaction.get(docRef);
      if (!existing.exists) {
        throw StateError('Relationship $id not found');
      }
      final data = existing.data()!;
      if (data['trainerId'] != callerUserId || data['athleteId'] != athleteId) {
        throw StateError('Relationship $id is not owned by $callerUserId');
      }
      if (data['status'] != TrainerClientRelationshipStatus.active.name) {
        throw StateError('Relationship $id is not active');
      }
      transaction.update(docRef, {
        'status': TrainerClientRelationshipStatus.ended.name,
        'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': callerUserId,
      });
    });
  }

  Stream<List<TrainerClientRelationship>> watchClients(String trainerId) {
    return _collection
        .where('trainerId', isEqualTo: trainerId)
        .where(
          'status',
          isEqualTo: TrainerClientRelationshipStatus.active.name,
        )
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
        .where(
          'status',
          isEqualTo: TrainerClientRelationshipStatus.active.name,
        )
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

  TrainerClientRelationship _fromMap(
    Map<String, dynamic> data,
    String id,
  ) {
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
