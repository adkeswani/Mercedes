import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/relationships/data/trainer_client_relationship_repository.dart';
import 'package:stage5/features/relationships/domain/trainer_client_relationship.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  group('TrainerClientRelationship', () {
    test('validates an active relationship', () {
      final relationship = TrainerClientRelationship(
        id: 'trainer1_athlete1',
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        status: TrainerClientRelationshipStatus.active,
        startedAt: now,
        createdAt: now,
        createdBy: 'trainer1',
        updatedAt: now,
        updatedBy: 'trainer1',
      );

      expect(() => relationship.validate(), returnsNormally);
      expect(relationship.isActive, isTrue);
    });

    test('requires endedAt for an ended relationship', () {
      final relationship = TrainerClientRelationship(
        id: 'trainer1_athlete1',
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        status: TrainerClientRelationshipStatus.ended,
        startedAt: now,
        createdAt: now,
        createdBy: 'trainer1',
        updatedAt: now,
        updatedBy: 'trainer1',
      );

      expect(() => relationship.validate(), throwsArgumentError);
    });

    test('rejects a self relationship', () {
      final relationship = TrainerClientRelationship(
        id: 'trainer1_trainer1',
        trainerId: 'trainer1',
        athleteId: 'trainer1',
        status: TrainerClientRelationshipStatus.active,
        startedAt: now,
        createdAt: now,
        createdBy: 'trainer1',
        updatedAt: now,
        updatedBy: 'trainer1',
      );

      expect(() => relationship.validate(), throwsArgumentError);
    });
  });

  group('TrainerClientRelationshipRepository', () {
    late FakeFirebaseFirestore firestore;
    late TrainerClientRelationshipRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = TrainerClientRelationshipRepository(firestore: firestore);
    });

    test('uses a deterministic relationship id', () {
      expect(
        TrainerClientRelationshipRepository.relationshipId(
          'trainer1',
          'athlete1',
        ),
        'trainer1_athlete1',
      );
    });

    test('starts and reads an active relationship', () async {
      final id = await repository.startRelationship(
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        callerUserId: 'trainer1',
      );

      final relationship =
          await repository.getRelationship('trainer1', 'athlete1');
      expect(id, 'trainer1_athlete1');
      expect(relationship!.isActive, isTrue);
      expect(relationship.trainerId, 'trainer1');
      expect(relationship.athleteId, 'athlete1');
      expect(relationship.createdBy, 'trainer1');
    });

    test('rejects a start by a non-owner', () {
      expect(
        () => repository.startRelationship(
          trainerId: 'trainer1',
          athleteId: 'athlete1',
          callerUserId: 'stranger',
        ),
        throwsStateError,
      );
    });

    test('ends a relationship and excludes it from active clients', () async {
      await repository.startRelationship(
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        callerUserId: 'trainer1',
      );

      await repository.endRelationship(
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        callerUserId: 'trainer1',
      );

      final relationship =
          await repository.getRelationship('trainer1', 'athlete1');
      expect(relationship!.isEnded, isTrue);
      expect(relationship.endedAt, isNotNull);
      expect(await repository.watchClients('trainer1').first, isEmpty);
    });

    test('rejects ending another trainer relationship', () async {
      await repository.startRelationship(
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        callerUserId: 'trainer1',
      );

      expect(
        () => repository.endRelationship(
          trainerId: 'trainer1',
          athleteId: 'athlete1',
          callerUserId: 'stranger',
        ),
        throwsStateError,
      );
    });

    test('reactivates an ended relationship', () async {
      await repository.startRelationship(
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        callerUserId: 'trainer1',
      );
      await repository.endRelationship(
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        callerUserId: 'trainer1',
      );

      await repository.startRelationship(
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        callerUserId: 'trainer1',
      );

      final relationship =
          await repository.getRelationship('trainer1', 'athlete1');
      expect(relationship!.isActive, isTrue);
      expect(relationship.endedAt, isNull);
    });

    test('streams active trainers for an athlete', () async {
      await repository.startRelationship(
        trainerId: 'trainer1',
        athleteId: 'athlete1',
        callerUserId: 'trainer1',
      );
      await repository.startRelationship(
        trainerId: 'trainer2',
        athleteId: 'athlete1',
        callerUserId: 'trainer2',
      );

      final relationships = await repository.watchTrainers('athlete1').first;
      expect(
        relationships.map((relationship) => relationship.trainerId),
        containsAll(['trainer1', 'trainer2']),
      );
    });

    group('legacy enrollment backfill', () {
      Future<void> seedProgram(
        String id, {
        String ownerId = 'trainer1',
        ProgramType type = ProgramType.assignable,
      }) {
        return firestore.collection('programs').doc(id).set({
          'ownerId': ownerId,
          'type': type.name,
        });
      }

      Future<void> seedEnrollment(
        String id, {
        String programId = 'program1',
        String athleteId = 'athlete1',
        String addedBy = 'trainer1',
        EnrollmentStatus status = EnrollmentStatus.active,
      }) {
        return firestore.collection('enrollments').doc(id).set({
          'programId': programId,
          'athleteId': athleteId,
          'addedBy': addedBy,
          'status': status.name,
        });
      }

      test('creates one relationship per athlete from active enrollments',
          () async {
        await seedProgram('program1');
        await seedProgram('program2');
        await seedEnrollment('enrollment1');
        await seedEnrollment(
          'enrollment2',
          programId: 'program2',
        );

        expect(
          await repository.backfillActiveEnrollmentRelationships(
            trainerId: 'trainer1',
            callerUserId: 'trainer1',
          ),
          1,
        );
        final relationship =
            await repository.getRelationship('trainer1', 'athlete1');
        expect(relationship, isNotNull);
        expect(relationship!.isActive, isTrue);
        expect(relationship.createdBy, 'trainer1');
      });

      test('is idempotent and never reactivates an ended relationship',
          () async {
        await seedProgram('program1');
        await seedEnrollment('enrollment1');
        await repository.startRelationship(
          trainerId: 'trainer1',
          athleteId: 'athlete1',
          callerUserId: 'trainer1',
        );
        await repository.endRelationship(
          trainerId: 'trainer1',
          athleteId: 'athlete1',
          callerUserId: 'trainer1',
        );

        expect(
          await repository.backfillActiveEnrollmentRelationships(
            trainerId: 'trainer1',
            callerUserId: 'trainer1',
          ),
          0,
        );
        final relationship =
            await repository.getRelationship('trainer1', 'athlete1');
        expect(relationship!.isEnded, isTrue);
      });

      test('ignores removed enrollments and personal self-enrollments',
          () async {
        await seedProgram('program1');
        await seedProgram(
          'personal',
          type: ProgramType.personal,
        );
        await seedEnrollment(
          'removed',
          status: EnrollmentStatus.removed,
        );
        await seedEnrollment(
          'self',
          programId: 'personal',
          athleteId: 'trainer1',
        );

        expect(
          await repository.backfillActiveEnrollmentRelationships(
            trainerId: 'trainer1',
            callerUserId: 'trainer1',
          ),
          0,
        );
        final relationships =
            await firestore.collection('trainerClientRelationships').get();
        expect(relationships.docs, isEmpty);
      });

      test('rejects a caller who does not own the roster', () {
        expect(
          () => repository.backfillActiveEnrollmentRelationships(
            trainerId: 'trainer1',
            callerUserId: 'stranger',
          ),
          throwsStateError,
        );
      });

      test('rejects an enrollment whose program has another owner', () async {
        await seedProgram('program1', ownerId: 'stranger');
        await seedEnrollment('enrollment1');

        expect(
          () => repository.backfillActiveEnrollmentRelationships(
            trainerId: 'trainer1',
            callerUserId: 'trainer1',
          ),
          throwsStateError,
        );
      });

      test('migrates when an enrolled program later became personal', () async {
        await seedProgram(
          'program1',
          type: ProgramType.personal,
        );
        await seedEnrollment('enrollment1');

        expect(
          await repository.backfillActiveEnrollmentRelationships(
            trainerId: 'trainer1',
            callerUserId: 'trainer1',
          ),
          1,
        );
        final relationship =
            await repository.getRelationship('trainer1', 'athlete1');
        expect(relationship!.isActive, isTrue);
      });
    });
  });
}
