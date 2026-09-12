import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/workouts/data/workout_instance_repository.dart';

void main() {
  test('history query returns only terminal and overdue athlete records',
      () async {
    final firestore = FakeFirebaseFirestore();
    final repository = WorkoutInstanceRepository(
      firestore: firestore,
      now: () => DateTime.utc(2026, 1, 1),
    );

    Future<void> seed(
      String id, {
      required String athleteId,
      required String date,
      required String status,
    }) {
      return firestore.collection('workoutInstances').doc(id).set({
        'programId': 'program-1',
        'athleteId': athleteId,
        'workoutTemplateId': 'workout-1',
        'workoutTemplateVersion': 1,
        'scheduledDate': date,
        'assignedBy': 'trainer-1',
        'assignedAt': DateTime.utc(2025),
        'status': status,
        'workoutType': 'fullBody',
        'completedAt':
            status == 'completed' ? DateTime.utc(2025, 12, 31) : null,
        'rpe': status == 'completed' ? 8 : null,
        'durationMinutes': status == 'completed' ? 45 : null,
        'createdAt': DateTime.utc(2025),
        'updatedAt': DateTime.utc(2025),
      });
    }

    await seed(
      'overdue',
      athleteId: 'athlete-1',
      date: '2025-12-20',
      status: 'scheduled',
    );
    await seed(
      'completed',
      athleteId: 'athlete-1',
      date: '2026-02-01',
      status: 'completed',
    );
    await seed(
      'future',
      athleteId: 'athlete-1',
      date: '2026-03-01',
      status: 'scheduled',
    );
    await seed(
      'other-athlete',
      athleteId: 'athlete-2',
      date: '2025-12-10',
      status: 'completed',
    );

    final history = await repository.watchHistory(athleteId: 'athlete-1').first;

    expect(history.map((item) => item.id), ['completed', 'overdue']);
    expect(history.every((item) => item.athleteId == 'athlete-1'), isTrue);
  });
}
