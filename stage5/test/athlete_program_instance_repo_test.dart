import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/programs/data/athlete_program_instance_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AthleteProgramInstanceRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = AthleteProgramInstanceRepository(
      firestore: firestore,
      now: () => DateTime.utc(2026, 1, 1),
    );
  });

  Future<void> seedSubscription() async {
    await firestore
        .collection('athleteProgramInstances')
        .doc('instance-1')
        .set({
      'athleteOwnerId': 'athlete-1',
      'assigningTrainerId': 'trainer-1',
      'sourceProgramId': 'program-1',
      'sourceProgramVersion': 2,
      'relationshipMode': 'subscribed',
      'startDate': '2026-01-01',
      'expectedEndDate': '2026-02-01',
      'workoutCount': 2,
      'status': 'active',
      'linkedAt': DateTime.utc(2026, 1, 1),
      'unlinkedAt': null,
      'unlinkReason': null,
      'materializationKey': null,
      'createdAt': DateTime.utc(2026, 1, 1),
      'createdBy': 'trainer-1',
      'updatedAt': DateTime.utc(2026, 1, 1),
      'updatedBy': 'trainer-1',
      'deletedAt': null,
      'deletedBy': null,
    });
  }

  test('structural conversion requires confirmation and athlete ownership',
      () async {
    await seedSubscription();
    await firestore.collection('workoutInstances').doc('future').set({
      'athleteProgramInstanceId': 'instance-1',
      'athleteId': 'athlete-1',
      'status': 'scheduled',
      'scheduledDate': '2026-01-10',
      'relationshipMode': 'subscribed',
    });
    await firestore.collection('workoutInstances').doc('completed').set({
      'athleteProgramInstanceId': 'instance-1',
      'athleteId': 'athlete-1',
      'status': 'completed',
      'scheduledDate': '2025-12-20',
      'relationshipMode': 'subscribed',
    });

    await expectLater(
      repository.convertSubscriptionToCopy(
        instanceId: 'instance-1',
        athleteId: 'athlete-1',
        confirmed: false,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.convertSubscriptionToCopy(
        instanceId: 'instance-1',
        athleteId: 'stranger',
        confirmed: true,
      ),
      throwsStateError,
    );

    await repository.convertSubscriptionToCopy(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      confirmed: true,
    );
    final converted = await repository.getById('instance-1');
    expect(converted!.isCopied, isTrue);
    expect(converted.unlinkReason, 'structuralCustomization');
    expect(converted.unlinkedAt, isNotNull);
    final future =
        await firestore.collection('workoutInstances').doc('future').get();
    expect(future.data()!['relationshipMode'], 'copied');
    final completed =
        await firestore.collection('workoutInstances').doc('completed').get();
    expect(completed.data()!['relationshipMode'], 'subscribed');
  });

  test('legacy backfill is conservative, linked, and idempotent', () async {
    await firestore.collection('workoutInstances').doc('workout-1').set({
      'programId': 'program-1',
      'programOwnerId': 'trainer-1',
      'programVersion': 2,
      'programAssignmentId': 'legacy-assignment',
      'athleteId': 'athlete-1',
      'assignedBy': 'trainer-1',
      'scheduledDate': '2026-01-03',
    });
    await firestore.collection('workoutInstances').doc('workout-2').set({
      'programId': 'program-1',
      'programOwnerId': 'trainer-1',
      'programVersion': 2,
      'programAssignmentId': 'legacy-assignment',
      'athleteId': 'athlete-1',
      'assignedBy': 'trainer-1',
      'scheduledDate': '2026-01-10',
    });

    expect(
      await repository.backfillLegacyAssignments(
        athleteId: 'athlete-1',
        actorId: 'athlete-1',
      ),
      1,
    );
    expect(
      await repository.backfillLegacyAssignments(
        athleteId: 'athlete-1',
        actorId: 'athlete-1',
      ),
      0,
    );

    final instance = await repository.getById('legacy-assignment');
    expect(instance!.isCopied, isTrue);
    expect(instance.startDate, '2026-01-03');
    expect(instance.expectedEndDate, '2026-01-10');
    for (final id in ['workout-1', 'workout-2']) {
      final workout =
          await firestore.collection('workoutInstances').doc(id).get();
      expect(
        workout.data()!['athleteProgramInstanceId'],
        'legacy-assignment',
      );
      expect(workout.data()!['relationshipMode'], 'copied');
    }
  });

  test('legacy backfill derives terminal parent lifecycle status', () async {
    for (final entry in {
      'cancelled-assignment': ['cancelled', 'cancelled'],
      'completed-assignment': ['completed', 'missed'],
    }.entries) {
      for (var i = 0; i < entry.value.length; i += 1) {
        await firestore
            .collection('workoutInstances')
            .doc('${entry.key}-$i')
            .set({
          'programId': 'program-1',
          'programOwnerId': 'trainer-1',
          'programVersion': 2,
          'programAssignmentId': entry.key,
          'athleteId': 'athlete-1',
          'assignedBy': 'trainer-1',
          'scheduledDate': '2025-12-${20 + i}',
          'status': entry.value[i],
        });
      }
    }

    expect(
      await repository.backfillLegacyAssignments(
        athleteId: 'athlete-1',
        actorId: 'athlete-1',
      ),
      2,
    );
    expect(
      (await repository.getById('cancelled-assignment'))!.status.name,
      'cancelled',
    );
    expect(
      (await repository.getById('completed-assignment'))!.status.name,
      'completed',
    );
  });

  test('legacy backfill chunks a 500-workout assignment', () async {
    for (var i = 0; i < 500; i += 1) {
      await firestore.collection('workoutInstances').doc('workout-$i').set({
        'programId': 'program-1',
        'programOwnerId': 'trainer-1',
        'programVersion': 2,
        'programAssignmentId': 'large-assignment',
        'athleteId': 'athlete-1',
        'assignedBy': 'trainer-1',
        'scheduledDate': '2026-01-03',
        'status': 'scheduled',
      });
    }

    expect(
      await repository.backfillLegacyAssignments(
        athleteId: 'athlete-1',
        actorId: 'athlete-1',
      ),
      1,
    );
    final migrated = await firestore
        .collection('workoutInstances')
        .where('athleteProgramInstanceId', isEqualTo: 'large-assignment')
        .get();
    expect(migrated.docs, hasLength(500));
  });

  test('legacy backfill rejects a non-owner', () async {
    await expectLater(
      repository.backfillLegacyAssignments(
        athleteId: 'athlete-1',
        actorId: 'trainer-1',
      ),
      throwsStateError,
    );
  });
}
