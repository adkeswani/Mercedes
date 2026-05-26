import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage3/core/enums.dart';
import 'package:stage3/features/programs/data/enrollment_repository.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late EnrollmentRepository repo;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repo = EnrollmentRepository(firestore: fakeFirestore);
  });

  /// Helper: creates a program doc so enrollment ownership checks pass.
  Future<void> createProgram(
    String id, {
    String ownerId = 'coach1',
    String type = 'assignable',
  }) async {
    await fakeFirestore.collection('programs').doc(id).set({
      'name': 'Test Program',
      'ownerId': ownerId,
      'type': type,
      'status': 'draft',
      'currentVersion': 0,
    });
  }

  group('EnrollmentRepository', () {
    group('enrollmentId', () {
      test('generates deterministic ID from programId and athleteId', () {
        expect(
          EnrollmentRepository.enrollmentId('prog1', 'athlete1'),
          'prog1_athlete1',
        );
      });
    });

    group('enrollAthlete', () {
      test('creates enrollment doc with correct fields', () async {
        await createProgram('prog1');
        final id = await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );

        expect(id, 'prog1_athlete1');

        final doc =
            await fakeFirestore.collection('enrollments').doc(id).get();
        expect(doc.exists, isTrue);
        expect(doc.data()!['programId'], 'prog1');
        expect(doc.data()!['athleteId'], 'athlete1');
        expect(doc.data()!['addedBy'], 'coach1');
        expect(doc.data()!['status'], 'active');
        expect(doc.data()!['removedAt'], isNull);
        expect(doc.data()!['removedBy'], isNull);
        expect(doc.data()!['createdBy'], 'coach1');
        expect(doc.data()!['deletedAt'], isNull);
      });

      test('throws when athlete is already actively enrolled', () async {
        await createProgram('prog1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );

        expect(
          () => repo.enrollAthlete(
            programId: 'prog1',
            athleteId: 'athlete1',
            addedBy: 'coach1',
          ),
          throwsStateError,
        );
      });

      test('allows re-enrollment after removal', () async {
        await createProgram('prog1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );

        await repo.removeAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          removedBy: 'coach1',
        );

        // Re-enroll should succeed
        final id = await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );

        expect(id, 'prog1_athlete1');

        final enrollment =
            await repo.getEnrollment('prog1', 'athlete1');
        expect(enrollment, isNotNull);
        expect(enrollment!.isActive, isTrue);
        expect(enrollment.removedAt, isNull);
      });
      test('throws when caller is not program owner', () async {
        await createProgram('prog1', ownerId: 'coach1');
        expect(
          () => repo.enrollAthlete(
            programId: 'prog1',
            athleteId: 'athlete1',
            addedBy: 'not_the_owner',
          ),
          throwsStateError,
        );
      });

      test('throws when program is personal', () async {
        await createProgram('prog1', type: 'personal');
        expect(
          () => repo.enrollAthlete(
            programId: 'prog1',
            athleteId: 'athlete1',
            addedBy: 'coach1',
          ),
          throwsStateError,
        );
      });

      test('throws when program does not exist', () async {
        expect(
          () => repo.enrollAthlete(
            programId: 'nonexistent',
            athleteId: 'athlete1',
            addedBy: 'coach1',
          ),
          throwsStateError,
        );
      });
    });

    group('removeAthlete', () {
      test('sets removal fields and status to removed', () async {
        await createProgram('prog1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );

        await repo.removeAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          removedBy: 'coach1',
        );

        final doc = await fakeFirestore
            .collection('enrollments')
            .doc('prog1_athlete1')
            .get();
        expect(doc.data()!['status'], 'removed');
        expect(doc.data()!['removedBy'], 'coach1');
      });

      test('throws when caller is not program owner', () async {
        await createProgram('prog1', ownerId: 'coach1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );

        expect(
          () => repo.removeAthlete(
            programId: 'prog1',
            athleteId: 'athlete1',
            removedBy: 'not_the_owner',
          ),
          throwsStateError,
        );
      });
    });

    group('watchEnrollments', () {
      test('streams active enrollments for a program', () async {
        await createProgram('prog1');
        await createProgram('prog2', ownerId: 'coach2');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete2',
          addedBy: 'coach1',
        );
        // Different program — should not appear
        await repo.enrollAthlete(
          programId: 'prog2',
          athleteId: 'athlete3',
          addedBy: 'coach2',
        );

        final enrollments = await repo.watchEnrollments('prog1').first;
        expect(enrollments.length, 2);
        expect(
          enrollments.map((e) => e.athleteId),
          containsAll(['athlete1', 'athlete2']),
        );
      });

      test('excludes removed enrollments', () async {
        await createProgram('prog1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete2',
          addedBy: 'coach1',
        );

        await repo.removeAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          removedBy: 'coach1',
        );

        final enrollments = await repo.watchEnrollments('prog1').first;
        expect(enrollments.length, 1);
        expect(enrollments.first.athleteId, 'athlete2');
      });
    });

    group('watchMyEnrollments', () {
      test('streams active enrollments for an athlete', () async {
        await createProgram('prog1');
        await createProgram('prog2', ownerId: 'coach2');
        await createProgram('prog3');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );
        await repo.enrollAthlete(
          programId: 'prog2',
          athleteId: 'athlete1',
          addedBy: 'coach2',
        );
        // Different athlete — should not appear
        await repo.enrollAthlete(
          programId: 'prog3',
          athleteId: 'athlete2',
          addedBy: 'coach1',
        );

        final enrollments =
            await repo.watchMyEnrollments('athlete1').first;
        expect(enrollments.length, 2);
        expect(
          enrollments.map((e) => e.programId),
          containsAll(['prog1', 'prog2']),
        );
      });

      test('excludes removed enrollments', () async {
        await createProgram('prog1');
        await createProgram('prog2', ownerId: 'coach2');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );
        await repo.enrollAthlete(
          programId: 'prog2',
          athleteId: 'athlete1',
          addedBy: 'coach2',
        );

        await repo.removeAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          removedBy: 'coach1',
        );

        final enrollments =
            await repo.watchMyEnrollments('athlete1').first;
        expect(enrollments.length, 1);
        expect(enrollments.first.programId, 'prog2');
      });
    });

    group('isEnrolled', () {
      test('returns true for active enrollment', () async {
        await createProgram('prog1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );

        final result = await repo.isEnrolled('prog1', 'athlete1');
        expect(result, isTrue);
      });

      test('returns false for removed enrollment', () async {
        await createProgram('prog1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );
        await repo.removeAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          removedBy: 'coach1',
        );

        final result = await repo.isEnrolled('prog1', 'athlete1');
        expect(result, isFalse);
      });

      test('returns false for non-existent enrollment', () async {
        final result = await repo.isEnrolled('prog1', 'athlete1');
        expect(result, isFalse);
      });
    });

    group('getEnrollment', () {
      test('returns enrollment when it exists', () async {
        await createProgram('prog1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );

        final enrollment =
            await repo.getEnrollment('prog1', 'athlete1');
        expect(enrollment, isNotNull);
        expect(enrollment!.programId, 'prog1');
        expect(enrollment.athleteId, 'athlete1');
        expect(enrollment.isActive, isTrue);
      });

      test('returns null for non-existent enrollment', () async {
        final enrollment =
            await repo.getEnrollment('prog1', 'athlete1');
        expect(enrollment, isNull);
      });

      test('returns removed enrollment (not null)', () async {
        await createProgram('prog1');
        await repo.enrollAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          addedBy: 'coach1',
        );
        await repo.removeAthlete(
          programId: 'prog1',
          athleteId: 'athlete1',
          removedBy: 'coach1',
        );

        final enrollment =
            await repo.getEnrollment('prog1', 'athlete1');
        expect(enrollment, isNotNull);
        expect(enrollment!.isRemoved, isTrue);
        expect(enrollment.removedBy, 'coach1');
      });
    });
  });
}
