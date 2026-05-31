import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage3/core/enums.dart';
import 'package:stage3/features/workouts/data/workout_instance_repository.dart';
import 'package:stage3/features/workouts/domain/workout_instance.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late WorkoutInstanceRepository repo;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repo = WorkoutInstanceRepository(firestore: fakeFirestore);
  });

  /// Helper: creates a program doc for ownership checks.
  Future<void> createProgram(
    String id, {
    String ownerId = 'coach1',
    String type = 'assignable',
  }) async {
    await fakeFirestore.collection('programs').doc(id).set({
      'name': 'Test Program',
      'ownerId': ownerId,
      'type': type,
      'status': 'published',
      'currentVersion': 1,
    });
  }

  /// Helper: creates an active enrollment doc.
  Future<void> enrollAthlete(String programId, String athleteId) async {
    await fakeFirestore
        .collection('enrollments')
        .doc('${programId}_$athleteId')
        .set({
      'programId': programId,
      'athleteId': athleteId,
      'status': 'active',
      'addedBy': 'coach1',
    });
  }

  /// Helper: assigns a workout and returns the instance ID.
  Future<String> assignWorkout({
    String programId = 'prog1',
    String athleteId = 'athlete1',
    String assignedBy = 'coach1',
    String scheduledDate = '2026-06-01',
    WorkoutType workoutType = WorkoutType.pull,
  }) async {
    return repo.assignWorkout(
      programId: programId,
      athleteId: athleteId,
      workoutTemplateId: 'wt1',
      workoutTemplateVersion: 1,
      scheduledDate: scheduledDate,
      workoutType: workoutType,
      assignedBy: assignedBy,
    );
  }

  group('WorkoutInstanceRepository', () {
    group('assignWorkout', () {
      test('creates scheduled instance with correct fields', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final id = await assignWorkout();

        expect(id, isNotEmpty);
        final doc = await fakeFirestore
            .collection('workoutInstances')
            .doc(id)
            .get();
        expect(doc.exists, isTrue);
        expect(doc.data()!['programId'], 'prog1');
        expect(doc.data()!['athleteId'], 'athlete1');
        expect(doc.data()!['workoutTemplateId'], 'wt1');
        expect(doc.data()!['workoutTemplateVersion'], 1);
        expect(doc.data()!['scheduledDate'], '2026-06-01');
        expect(doc.data()!['status'], 'scheduled');
        expect(doc.data()!['workoutType'], 'pull');
        expect(doc.data()!['assignedBy'], 'coach1');
        expect(doc.data()!['completedAt'], isNull);
        expect(doc.data()!['missedAt'], isNull);
      });

      test('throws when caller is not program owner', () async {
        await createProgram('prog1', ownerId: 'coach1');
        await enrollAthlete('prog1', 'athlete1');

        expect(
          () => assignWorkout(assignedBy: 'not_the_owner'),
          throwsStateError,
        );
      });

      test('throws when athlete is not enrolled', () async {
        await createProgram('prog1');
        // No enrollment created

        expect(
          () => assignWorkout(),
          throwsStateError,
        );
      });

      test('throws when program does not exist', () async {
        expect(
          () => assignWorkout(programId: 'nonexistent'),
          throwsStateError,
        );
      });

      test('allows self-assignment for personal programs', () async {
        await createProgram('prog1', ownerId: 'athlete1', type: 'personal');

        final id = await assignWorkout(
          programId: 'prog1',
          athleteId: 'athlete1',
          assignedBy: 'athlete1',
        );

        expect(id, isNotEmpty);
      });

      test('blocks non-self assignment for personal programs', () async {
        await createProgram('prog1', ownerId: 'coach1', type: 'personal');

        expect(
          () => assignWorkout(
            programId: 'prog1',
            athleteId: 'athlete1',
            assignedBy: 'coach1',
          ),
          throwsStateError,
        );
      });
    });

    group('completeWorkout', () {
      test('sets completion fields', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout();

        await repo.completeWorkout(
          instanceId: id,
          rpe: 7,
          durationMinutes: 55,
          actuals: [
            ExerciseActual(
              exerciseId: 'ex1',
              mode: ExerciseMode.reps,
              sets: 3,
              reps: '10',
              weight: '135 lb',
            ),
          ],
          loadPoints: 20.0,
          athleteNotes: 'Felt strong',
        );

        final doc = await fakeFirestore
            .collection('workoutInstances')
            .doc(id)
            .get();
        expect(doc.data()!['status'], 'completed');
        expect(doc.data()!['rpe'], 7);
        expect(doc.data()!['durationMinutes'], 55);
        expect(doc.data()!['loadPoints'], 20.0);
        expect(doc.data()!['athleteNotes'], 'Felt strong');
        expect(doc.data()!['actuals'], isA<List>());
        expect((doc.data()!['actuals'] as List).length, 1);
      });

      test('completed instance is retrievable', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout();

        await repo.completeWorkout(
          instanceId: id,
          rpe: 8,
          durationMinutes: 45,
          actuals: [],
        );

        final instance = await repo.getById(id);
        expect(instance, isNotNull);
        expect(instance!.isCompleted, isTrue);
        expect(instance.rpe, 8);
        expect(instance.durationMinutes, 45);
      });
    });

    group('cancelFutureInstances', () {
      test('cancels scheduled instances for program-athlete pair', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final id1 = await assignWorkout(scheduledDate: '2026-06-01');
        final id2 = await assignWorkout(scheduledDate: '2026-06-02');

        final count = await repo.cancelFutureInstances(
          programId: 'prog1',
          athleteId: 'athlete1',
        );

        expect(count, 2);

        final i1 = await repo.getById(id1);
        final i2 = await repo.getById(id2);
        expect(i1!.status, WorkoutInstanceStatus.cancelled);
        expect(i2!.status, WorkoutInstanceStatus.cancelled);
      });

      test('does not cancel completed instances', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final id1 = await assignWorkout(scheduledDate: '2026-06-01');
        final id2 = await assignWorkout(scheduledDate: '2026-06-02');

        // Complete the first one
        await repo.completeWorkout(
          instanceId: id1,
          rpe: 7,
          durationMinutes: 50,
          actuals: [],
        );

        final count = await repo.cancelFutureInstances(
          programId: 'prog1',
          athleteId: 'athlete1',
        );

        expect(count, 1); // Only the scheduled one
        final i1 = await repo.getById(id1);
        final i2 = await repo.getById(id2);
        expect(i1!.isCompleted, isTrue); // Preserved
        expect(i2!.status, WorkoutInstanceStatus.cancelled);
      });

      test('does not cancel instances for other athletes', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        await enrollAthlete('prog1', 'athlete2');

        await assignWorkout(
          athleteId: 'athlete1',
          scheduledDate: '2026-06-01',
        );
        final otherId = await assignWorkout(
          athleteId: 'athlete2',
          scheduledDate: '2026-06-01',
        );

        await repo.cancelFutureInstances(
          programId: 'prog1',
          athleteId: 'athlete1',
        );

        final other = await repo.getById(otherId);
        expect(other!.isScheduled, isTrue); // Untouched
      });
    });

    group('watchSchedule', () {
      test('streams instances within date range', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        await assignWorkout(scheduledDate: '2026-06-01');
        await assignWorkout(scheduledDate: '2026-06-05');
        await assignWorkout(scheduledDate: '2026-06-10');

        final instances = await repo
            .watchSchedule(
              athleteId: 'athlete1',
              startDate: '2026-06-01',
              endDate: '2026-06-07',
            )
            .first;

        expect(instances.length, 2);
        expect(instances[0].scheduledDate, '2026-06-01');
        expect(instances[1].scheduledDate, '2026-06-05');
      });
    });

    group('watchProgramSchedule', () {
      test('streams instances for a program-athlete pair', () async {
        await createProgram('prog1');
        await createProgram('prog2');
        await enrollAthlete('prog1', 'athlete1');
        await enrollAthlete('prog2', 'athlete1');

        await assignWorkout(programId: 'prog1', scheduledDate: '2026-06-01');
        await assignWorkout(programId: 'prog2', scheduledDate: '2026-06-02');

        final instances = await repo
            .watchProgramSchedule(
              programId: 'prog1',
              athleteId: 'athlete1',
            )
            .first;

        expect(instances.length, 1);
        expect(instances.first.programId, 'prog1');
      });
    });

    group('getById', () {
      test('returns instance when it exists', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout();

        final instance = await repo.getById(id);
        expect(instance, isNotNull);
        expect(instance!.programId, 'prog1');
        expect(instance.isScheduled, isTrue);
      });

      test('returns null for non-existent ID', () async {
        final instance = await repo.getById('nonexistent');
        expect(instance, isNull);
      });
    });

    group('serialization', () {
      test('round-trips all fields through Firestore', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final id = await assignWorkout(
          workoutType: WorkoutType.power,
          scheduledDate: '2026-07-15',
        );

        await repo.completeWorkout(
          instanceId: id,
          rpe: 9,
          durationMinutes: 60,
          actuals: [
            ExerciseActual(
              exerciseId: 'ex1',
              mode: ExerciseMode.reps,
              sets: 4,
              reps: '8-10',
              weight: '185 lb',
              restSeconds: 120,
              notes: 'Pause at bottom',
            ),
            ExerciseActual(
              exerciseId: 'ex2',
              mode: ExerciseMode.time,
              durationSeconds: 30,
            ),
          ],
          loadPoints: 28.5,
          loadStrategyId: 'climbing_v1',
          athleteNotes: 'Great session',
        );

        final instance = await repo.getById(id);
        expect(instance, isNotNull);
        expect(instance!.workoutType, WorkoutType.power);
        expect(instance.scheduledDate, '2026-07-15');
        expect(instance.rpe, 9);
        expect(instance.durationMinutes, 60);
        expect(instance.loadPoints, 28.5);
        expect(instance.loadStrategyId, 'climbing_v1');
        expect(instance.athleteNotes, 'Great session');
        expect(instance.actuals.length, 2);
        expect(instance.actuals[0].exerciseId, 'ex1');
        expect(instance.actuals[0].sets, 4);
        expect(instance.actuals[0].reps, '8-10');
        expect(instance.actuals[0].weight, '185 lb');
        expect(instance.actuals[0].restSeconds, 120);
        expect(instance.actuals[1].mode, ExerciseMode.time);
        expect(instance.actuals[1].durationSeconds, 30);
      });
    });
  });
}
