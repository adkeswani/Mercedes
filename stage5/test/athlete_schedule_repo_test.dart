import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/workouts/data/workout_instance_repository.dart';

void main() {
  test('calendar reads legacy workouts without lifecycle recovery writes',
      () async {
    final firestore = FakeFirebaseFirestore();
    final repository = WorkoutInstanceRepository(firestore: firestore);
    await firestore
        .collection('athleteProgramInstances')
        .doc('unrelated-active')
        .set({
      'athleteOwnerId': 'athlete-1',
      'status': 'active',
    });
    await firestore.collection('workoutInstances').doc('legacy-own').set({
      'programId': 'program-1',
      'athleteId': 'athlete-1',
      'workoutTemplateId': 'workout-1',
      'workoutTemplateVersion': 1,
      'scheduledDate': '2026-09-12',
      'assignedBy': 'trainer-1',
      'assignedAt': DateTime.utc(2026, 9, 1),
      'status': 'scheduled',
      'workoutType': 'fullBody',
      'createdAt': DateTime.utc(2026, 9, 1),
      'updatedAt': DateTime.utc(2026, 9, 1),
    });
    await firestore.collection('workoutInstances').doc('other-athlete').set({
      'programId': 'program-1',
      'athleteId': 'athlete-2',
      'workoutTemplateId': 'workout-1',
      'workoutTemplateVersion': 1,
      'scheduledDate': '2026-09-12',
      'assignedBy': 'trainer-1',
      'assignedAt': DateTime.utc(2026, 9, 1),
      'status': 'scheduled',
      'workoutType': 'fullBody',
      'createdAt': DateTime.utc(2026, 9, 1),
      'updatedAt': DateTime.utc(2026, 9, 1),
    });

    final schedule = await repository
        .watchSchedule(
          athleteId: 'athlete-1',
          startDate: '2026-09-08',
          endDate: '2026-09-14',
        )
        .first;

    expect(schedule.map((item) => item.id), ['legacy-own']);
    final programInstance = await firestore
        .collection('athleteProgramInstances')
        .doc('unrelated-active')
        .get();
    expect(programInstance.data()!['status'], 'active');
  });
}
