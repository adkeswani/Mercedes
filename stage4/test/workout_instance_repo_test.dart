import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/workouts/data/workout_instance_repository.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';

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

    group('updateCompletion', () {
      test('updates completion fields on already-completed instance', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout();

        await repo.completeWorkout(
          instanceId: id,
          rpe: 6,
          durationMinutes: 40,
          actuals: [],
          athleteNotes: 'Original notes',
        );

        await repo.updateCompletion(
          instanceId: id,
          rpe: 8,
          durationMinutes: 55,
          actuals: [
            ExerciseActual(
              exerciseId: 'ex1',
              mode: ExerciseMode.reps,
              sets: 4,
              reps: '8',
            ),
          ],
          athleteNotes: 'Updated notes',
          loadPoints: 25.0,
        );

        final instance = await repo.getById(id);
        expect(instance, isNotNull);
        expect(instance!.isCompleted, isTrue);
        expect(instance.rpe, 8);
        expect(instance.durationMinutes, 55);
        expect(instance.athleteNotes, 'Updated notes');
        expect(instance.loadPoints, 25.0);
        expect(instance.actuals.length, 1);
        expect(instance.actuals.first.exerciseId, 'ex1');
      });

      test('preserves status and completedAt when updating', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout();

        await repo.completeWorkout(
          instanceId: id,
          rpe: 5,
          durationMinutes: 30,
          actuals: [],
        );

        final before = await repo.getById(id);

        await repo.updateCompletion(
          instanceId: id,
          rpe: 9,
          durationMinutes: 60,
          actuals: [],
        );

        final after = await repo.getById(id);
        expect(after!.status, before!.status);
        expect(after.completedAt, before.completedAt);
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

    group('assignRecurringWorkouts', () {
      test('creates batch of instances with recurrence fields', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final recurrence = Recurrence(
          pattern: RecurrencePattern.weekly,
          daysOfWeek: [1, 3], // Mon, Wed
          endDate: '2026-06-28',
        );

        final count = await repo.assignRecurringWorkouts(
          programId: 'prog1',
          athleteId: 'athlete1',
          workoutTemplateId: 'wt1',
          workoutTemplateVersion: 1,
          startDate: '2026-06-15', // Monday
          workoutType: WorkoutType.pull,
          assignedBy: 'coach1',
          recurrence: recurrence,
        );

        // Mon 15, Wed 17, Mon 22, Wed 24 = 4
        expect(count, 4);

        final snapshot = await fakeFirestore
            .collection('workoutInstances')
            .get();
        expect(snapshot.docs.length, 4);
      });

      test('first instance is root, rest have recurrenceRootId', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final recurrence = Recurrence(
          pattern: RecurrencePattern.custom,
          intervalDays: 7,
          endDate: '2026-07-06',
        );

        await repo.assignRecurringWorkouts(
          programId: 'prog1',
          athleteId: 'athlete1',
          workoutTemplateId: 'wt1',
          workoutTemplateVersion: 1,
          startDate: '2026-06-15',
          workoutType: WorkoutType.push,
          assignedBy: 'coach1',
          recurrence: recurrence,
        );

        final snapshot = await fakeFirestore
            .collection('workoutInstances')
            .get();
        final docs = snapshot.docs;
        expect(docs.length, 4); // Jun 15, 22, 29, Jul 6

        // Find the root
        final rootDocs = docs
            .where((d) => d.data()['isRecurrenceRoot'] == true)
            .toList();
        expect(rootDocs.length, 1);
        final rootId = rootDocs.first.id;

        // All children reference the root
        final children = docs
            .where((d) => d.data()['isRecurrenceRoot'] != true)
            .toList();
        for (final child in children) {
          expect(child.data()['recurrenceRootId'], rootId);
        }
      });

      test('stores recurrence pattern on all instances', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final recurrence = Recurrence(
          pattern: RecurrencePattern.biweekly,
          daysOfWeek: [5], // Friday
          endDate: '2026-07-17',
        );

        await repo.assignRecurringWorkouts(
          programId: 'prog1',
          athleteId: 'athlete1',
          workoutTemplateId: 'wt1',
          workoutTemplateVersion: 2,
          startDate: '2026-06-19', // Friday
          workoutType: WorkoutType.legs,
          assignedBy: 'coach1',
          recurrence: recurrence,
        );

        final snapshot = await fakeFirestore
            .collection('workoutInstances')
            .get();
        for (final doc in snapshot.docs) {
          final rec = doc.data()['recurrence'] as Map<String, dynamic>;
          expect(rec['pattern'], 'biweekly');
          expect(rec['endDate'], '2026-07-17');
        }
      });

      test('returns 0 when recurrence generates no dates', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final recurrence = Recurrence(
          pattern: RecurrencePattern.weekly,
          daysOfWeek: [1],
          endDate: '2026-06-10', // Before start
        );

        final count = await repo.assignRecurringWorkouts(
          programId: 'prog1',
          athleteId: 'athlete1',
          workoutTemplateId: 'wt1',
          workoutTemplateVersion: 1,
          startDate: '2026-06-15',
          workoutType: WorkoutType.pull,
          assignedBy: 'coach1',
          recurrence: recurrence,
        );

        expect(count, 0);
      });

      test('verifies ownership before creating', () async {
        await createProgram('prog1', ownerId: 'coach1');
        await enrollAthlete('prog1', 'athlete1');

        final recurrence = Recurrence(
          pattern: RecurrencePattern.weekly,
          daysOfWeek: [1],
          endDate: '2026-06-30',
        );

        expect(
          () => repo.assignRecurringWorkouts(
            programId: 'prog1',
            athleteId: 'athlete1',
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            startDate: '2026-06-15',
            workoutType: WorkoutType.pull,
            assignedBy: 'not_owner',
            recurrence: recurrence,
          ),
          throwsStateError,
        );
      });
    });

    group('cancelRecurrence', () {
      test('cancels all scheduled instances in recurrence group', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final recurrence = Recurrence(
          pattern: RecurrencePattern.custom,
          intervalDays: 7,
          endDate: '2026-07-06',
        );

        await repo.assignRecurringWorkouts(
          programId: 'prog1',
          athleteId: 'athlete1',
          workoutTemplateId: 'wt1',
          workoutTemplateVersion: 1,
          startDate: '2026-06-15',
          workoutType: WorkoutType.pull,
          assignedBy: 'coach1',
          recurrence: recurrence,
        );

        // Find the root
        final snapshot = await fakeFirestore
            .collection('workoutInstances')
            .get();
        final rootDoc = snapshot.docs
            .firstWhere((d) => d.data()['isRecurrenceRoot'] == true);

        final cancelled = await repo.cancelRecurrence(
          recurrenceRootId: rootDoc.id,
        );

        expect(cancelled, 4); // All 4 instances

        // Verify all are cancelled
        final after = await fakeFirestore
            .collection('workoutInstances')
            .get();
        for (final doc in after.docs) {
          expect(doc.data()['status'], 'cancelled');
        }
      });

      test('preserves completed instances in recurrence', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');

        final recurrence = Recurrence(
          pattern: RecurrencePattern.custom,
          intervalDays: 7,
          endDate: '2026-06-29',
        );

        await repo.assignRecurringWorkouts(
          programId: 'prog1',
          athleteId: 'athlete1',
          workoutTemplateId: 'wt1',
          workoutTemplateVersion: 1,
          startDate: '2026-06-15',
          workoutType: WorkoutType.pull,
          assignedBy: 'coach1',
          recurrence: recurrence,
        );

        // Complete the root instance
        final snapshot = await fakeFirestore
            .collection('workoutInstances')
            .get();
        final rootDoc = snapshot.docs
            .firstWhere((d) => d.data()['isRecurrenceRoot'] == true);

        await repo.completeWorkout(
          instanceId: rootDoc.id,
          rpe: 7,
          durationMinutes: 45,
          actuals: [],
        );

        final cancelled = await repo.cancelRecurrence(
          recurrenceRootId: rootDoc.id,
        );

        // 3 instances: Jun 15 (root, completed), Jun 22, Jun 29
        // Only 2 scheduled should be cancelled
        expect(cancelled, 2);

        final completed = await repo.getById(rootDoc.id);
        expect(completed!.isCompleted, isTrue);
      });
    });

    group('assignProgram', () {
      Future<void> publishVersion(
        String programId,
        List<Map<String, dynamic>> entries,
      ) async {
        await fakeFirestore
            .collection('programs')
            .doc(programId)
            .collection('programVersions')
            .doc('1')
            .set({
          'versionNumber': 1,
          'entries': entries,
        });
      }

      Future<void> createWorkoutTemplate(String id, String workoutType) async {
        await fakeFirestore.collection('workoutTemplates').doc(id).set({
          'name': 'WT $id',
          'workoutType': workoutType,
        });
      }

      test('materializes entries at startDate + dayOffset', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        await createWorkoutTemplate('wt1', 'push');
        await createWorkoutTemplate('wt2', 'pull');
        await publishVersion('prog1', [
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 0,
            'sortOrder': 0,
          },
          {
            'workoutTemplateId': 'wt2',
            'workoutTemplateVersion': 1,
            'dayOffset': 3,
            'sortOrder': 1,
          },
        ]);

        final result = await repo.assignProgram(
          programId: 'prog1',
          athleteId: 'athlete1',
          startDate: '2026-06-01',
          assignedBy: 'coach1',
        );

        expect(result.instanceCount, 2);
        expect(result.assignmentId, isNotEmpty);

        final snapshot = await fakeFirestore
            .collection('workoutInstances')
            .where('programAssignmentId', isEqualTo: result.assignmentId)
            .get();
        expect(snapshot.docs.length, 2);

        final byTemplate = {
          for (final d in snapshot.docs) d.data()['workoutTemplateId']: d.data()
        };
        expect(byTemplate['wt1']!['scheduledDate'], '2026-06-01');
        expect(byTemplate['wt2']!['scheduledDate'], '2026-06-04');
        expect(byTemplate['wt1']!['workoutType'], 'push');
        expect(byTemplate['wt2']!['workoutType'], 'pull');
        expect(byTemplate['wt1']!['programVersion'], 1);
        expect(byTemplate['wt1']!['status'], 'scheduled');
      });

      test('rolls dayOffset across month boundaries', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        await createWorkoutTemplate('wt1', 'push');
        await publishVersion('prog1', [
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 5,
            'sortOrder': 0,
          },
        ]);

        final result = await repo.assignProgram(
          programId: 'prog1',
          athleteId: 'athlete1',
          startDate: '2026-06-29',
          assignedBy: 'coach1',
        );

        final snapshot = await fakeFirestore
            .collection('workoutInstances')
            .where('programAssignmentId', isEqualTo: result.assignmentId)
            .get();
        expect(snapshot.docs.first.data()['scheduledDate'], '2026-07-04');
      });

      test('auto-enrolls the athlete when not already enrolled', () async {
        await createProgram('prog1');
        await createWorkoutTemplate('wt1', 'push');
        await publishVersion('prog1', [
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 0,
            'sortOrder': 0,
          },
        ]);

        await repo.assignProgram(
          programId: 'prog1',
          athleteId: 'athlete1',
          startDate: '2026-06-01',
          assignedBy: 'coach1',
        );

        final enrollment = await fakeFirestore
            .collection('enrollments')
            .doc('prog1_athlete1')
            .get();
        expect(enrollment.exists, isTrue);
        expect(enrollment.data()!['status'], 'active');
      });

      test('throws when caller is not the program owner', () async {
        await createProgram('prog1');
        await createWorkoutTemplate('wt1', 'push');
        await publishVersion('prog1', [
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 0,
            'sortOrder': 0,
          },
        ]);

        expect(
          () => repo.assignProgram(
            programId: 'prog1',
            athleteId: 'athlete1',
            startDate: '2026-06-01',
            assignedBy: 'intruder',
          ),
          throwsStateError,
        );
      });

      test('throws when program has no published version', () async {
        await fakeFirestore.collection('programs').doc('prog1').set({
          'name': 'Draft',
          'ownerId': 'coach1',
          'type': 'assignable',
          'status': 'draft',
          'currentVersion': 0,
        });

        expect(
          () => repo.assignProgram(
            programId: 'prog1',
            athleteId: 'athlete1',
            startDate: '2026-06-01',
            assignedBy: 'coach1',
          ),
          throwsStateError,
        );
      });

      test('cancelProgramAssignment cancels only scheduled instances',
          () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        await createWorkoutTemplate('wt1', 'push');
        await publishVersion('prog1', [
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 0,
            'sortOrder': 0,
          },
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 7,
            'sortOrder': 1,
          },
        ]);

        final result = await repo.assignProgram(
          programId: 'prog1',
          athleteId: 'athlete1',
          startDate: '2026-06-01',
          assignedBy: 'coach1',
        );

        final cancelled = await repo.cancelProgramAssignment(
          programAssignmentId: result.assignmentId,
        );
        expect(cancelled, 2);

        final snapshot = await fakeFirestore
            .collection('workoutInstances')
            .where('programAssignmentId', isEqualTo: result.assignmentId)
            .get();
        for (final doc in snapshot.docs) {
          expect(doc.data()['status'], 'cancelled');
        }
      });

      test('deleteIncompleteProgramAssignment removes incomplete but keeps '
          'completed', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        await createWorkoutTemplate('wt1', 'push');
        await publishVersion('prog1', [
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 0,
            'sortOrder': 0,
          },
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 7,
            'sortOrder': 1,
          },
        ]);

        final result = await repo.assignProgram(
          programId: 'prog1',
          athleteId: 'athlete1',
          startDate: '2026-06-01',
          assignedBy: 'coach1',
        );
        // Mark one instance completed; it must survive the delete.
        final docs = await fakeFirestore
            .collection('workoutInstances')
            .where('programAssignmentId', isEqualTo: result.assignmentId)
            .get();
        await docs.docs.first.reference.update({'status': 'completed'});

        final deleted = await repo.deleteIncompleteProgramAssignment(
          programAssignmentId: result.assignmentId,
          ownerId: 'coach1',
        );
        expect(deleted, 1);

        final remaining = await fakeFirestore
            .collection('workoutInstances')
            .where('programAssignmentId', isEqualTo: result.assignmentId)
            .get();
        expect(remaining.docs.length, 1);
        expect(remaining.docs.first.data()['status'], 'completed');
      });

      test('deleteIncompleteProgramAssignment throws for non-owner and deletes '
          'nothing', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        await createWorkoutTemplate('wt1', 'push');
        await publishVersion('prog1', [
          {
            'workoutTemplateId': 'wt1',
            'workoutTemplateVersion': 1,
            'dayOffset': 0,
            'sortOrder': 0,
          },
        ]);

        final result = await repo.assignProgram(
          programId: 'prog1',
          athleteId: 'athlete1',
          startDate: '2026-06-01',
          assignedBy: 'coach1',
        );

        expect(
          () => repo.deleteIncompleteProgramAssignment(
            programAssignmentId: result.assignmentId,
            ownerId: 'intruder',
          ),
          throwsStateError,
        );
        final remaining = await fakeFirestore
            .collection('workoutInstances')
            .where('programAssignmentId', isEqualTo: result.assignmentId)
            .get();
        expect(remaining.docs.length, 1);
      });

      test('deleteInstance removes a single instance', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout(scheduledDate: '2026-06-05');

        await repo.deleteInstance(instanceId: id, ownerId: 'coach1');

        expect(await repo.getById(id), isNull);
      });

      test('deleteInstance throws when caller did not assign it', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout(scheduledDate: '2026-06-05');

        expect(
          () => repo.deleteInstance(instanceId: id, ownerId: 'intruder'),
          throwsStateError,
        );
      });
    });

    group('watchAthleteCalendar', () {
      test('returns owner-assigned instances for the athlete in range',
          () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        await assignWorkout(scheduledDate: '2026-06-05');
        await assignWorkout(scheduledDate: '2026-06-20');
        // Out of range and other-athlete instances should be excluded.
        await assignWorkout(scheduledDate: '2026-07-05');

        final instances = await repo
            .watchAthleteCalendar(
              ownerId: 'coach1',
              athleteId: 'athlete1',
              startDate: '2026-06-01',
              endDate: '2026-06-30',
            )
            .first;

        expect(instances.length, 2);
        expect(
          instances.map((i) => i.scheduledDate).toList(),
          ['2026-06-05', '2026-06-20'],
        );
      });
    });

    group('rescheduleInstance', () {
      test('moves a scheduled instance to a new date', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout(scheduledDate: '2026-06-05');

        await repo.rescheduleInstance(
          instanceId: id,
          newDate: '2026-06-10',
          ownerId: 'coach1',
        );

        final doc = await fakeFirestore
            .collection('workoutInstances')
            .doc(id)
            .get();
        expect(doc.data()!['scheduledDate'], '2026-06-10');
      });

      test('throws when caller did not assign the instance', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout(scheduledDate: '2026-06-05');

        expect(
          () => repo.rescheduleInstance(
            instanceId: id,
            newDate: '2026-06-10',
            ownerId: 'intruder',
          ),
          throwsStateError,
        );
      });

      test('throws on invalid date format', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout(scheduledDate: '2026-06-05');

        expect(
          () => repo.rescheduleInstance(
            instanceId: id,
            newDate: 'June 10',
            ownerId: 'coach1',
          ),
          throwsArgumentError,
        );
      });
    });

    group('cancelInstance', () {
      test('cancels a scheduled instance', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout(scheduledDate: '2026-06-05');

        await repo.cancelInstance(instanceId: id, ownerId: 'coach1');

        final doc = await fakeFirestore
            .collection('workoutInstances')
            .doc(id)
            .get();
        expect(doc.data()!['status'], 'cancelled');
      });

      test('throws when caller did not assign the instance', () async {
        await createProgram('prog1');
        await enrollAthlete('prog1', 'athlete1');
        final id = await assignWorkout(scheduledDate: '2026-06-05');

        expect(
          () => repo.cancelInstance(instanceId: id, ownerId: 'intruder'),
          throwsStateError,
        );
      });
    });
  });
}
