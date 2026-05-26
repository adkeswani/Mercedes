import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage3/core/enums.dart';
import 'package:stage3/features/workouts/data/workout_template_repository.dart';
import 'package:stage3/features/workouts/domain/workout_template.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late WorkoutTemplateRepository repo;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repo = WorkoutTemplateRepository(firestore: fakeFirestore);
  });

  group('WorkoutTemplate.copyWith', () {
    test('returns copy with updated fields', () {
      final now = DateTime(2026, 1, 1);
      final template = WorkoutTemplate(
        id: 'wt1',
        name: 'Pull Day',
        workoutType: WorkoutType.pull,
        currentVersion: 1,
        createdAt: now,
        createdBy: 'user1',
        updatedAt: now,
        updatedBy: 'user1',
      );
      final updated = template.copyWith(
        name: 'Upper Pull',
        workoutType: WorkoutType.upper,
      );
      expect(updated.name, 'Upper Pull');
      expect(updated.workoutType, WorkoutType.upper);
      expect(updated.id, 'wt1');
      expect(updated.currentVersion, 1);
    });

    test('hasPublishedVersion reflects currentVersion', () {
      final now = DateTime(2026, 1, 1);
      final draft = WorkoutTemplate(
        id: 'wt1',
        name: 'Draft',
        workoutType: WorkoutType.fullBody,
        currentVersion: 0,
        createdAt: now,
        createdBy: 'user1',
        updatedAt: now,
        updatedBy: 'user1',
      );
      expect(draft.hasPublishedVersion, isFalse);

      final published = draft.copyWith(currentVersion: 1);
      expect(published.hasPublishedVersion, isTrue);
    });
  });

  group('ExercisePrescription.copyWith', () {
    test('returns copy with updated fields', () {
      final p = ExercisePrescription(
        exerciseId: 'ex1',
        sortOrder: 0,
        mode: ExerciseMode.reps,
        exerciseName: 'Squat',
        sets: 3,
        reps: '8-12',
      );
      final updated = p.copyWith(sets: 5, reps: '5');
      expect(updated.sets, 5);
      expect(updated.reps, '5');
      expect(updated.exerciseName, 'Squat');
      expect(updated.exerciseId, 'ex1');
    });
  });

  group('WorkoutTemplateRepository', () {
    test('create adds document with currentVersion 0', () async {
      final id = await repo.create(
        name: 'Push Day',
        workoutType: WorkoutType.push,
        userId: 'user1',
      );

      expect(id, isNotEmpty);
      final doc = await fakeFirestore
          .collection('workoutTemplates')
          .doc(id)
          .get();
      expect(doc.exists, true);
      expect(doc.data()!['name'], 'Push Day');
      expect(doc.data()!['workoutType'], 'push');
      expect(doc.data()!['currentVersion'], 0);
      expect(doc.data()!['createdBy'], 'user1');
    });

    test('getById returns template', () async {
      final id = await repo.create(
        name: 'Leg Day',
        workoutType: WorkoutType.legs,
        userId: 'user1',
      );

      final template = await repo.getById(id);
      expect(template, isNotNull);
      expect(template!.name, 'Leg Day');
      expect(template.workoutType, WorkoutType.legs);
      expect(template.currentVersion, 0);
    });

    test('getById returns null for non-existent', () async {
      final template = await repo.getById('nonexistent');
      expect(template, isNull);
    });

    test('getById returns template created by a different user', () async {
      final id = await repo.create(
        name: 'Coach Workout',
        workoutType: WorkoutType.pull,
        userId: 'coach1',
      );

      // Any user can read — getById has no ownership filter
      final template = await repo.getById(id);
      expect(template, isNotNull);
      expect(template!.name, 'Coach Workout');
    });

    test('getById returns null for soft-deleted', () async {
      final id = await repo.create(
        name: 'To Delete',
        workoutType: WorkoutType.core,
        userId: 'user1',
      );
      await repo.softDelete(id, 'user1');
      final template = await repo.getById(id);
      expect(template, isNull);
    });

    test('update modifies header fields', () async {
      final id = await repo.create(
        name: 'Day A',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      await repo.update(
        id: id,
        name: 'Upper Pull Day',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );

      final template = await repo.getById(id);
      expect(template!.name, 'Upper Pull Day');
      expect(template.workoutType, WorkoutType.pull);
    });

    test('softDelete sets deletedAt and deletedBy', () async {
      final id = await repo.create(
        name: 'Tempo',
        workoutType: WorkoutType.endurance,
        userId: 'user1',
      );

      await repo.softDelete(id, 'user1');

      final doc = await fakeFirestore
          .collection('workoutTemplates')
          .doc(id)
          .get();
      expect(doc.data()!['deletedBy'], 'user1');
      expect(doc.data()!['deletedAt'], isNotNull);
    });

    test('watchAll streams only non-deleted templates for user', () async {
      await repo.create(
        name: 'Workout A',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );
      final idB = await repo.create(
        name: 'Workout B',
        workoutType: WorkoutType.lower,
        userId: 'user1',
      );
      // Different user
      await repo.create(
        name: 'Workout C',
        workoutType: WorkoutType.core,
        userId: 'user2',
      );
      await repo.softDelete(idB, 'user1');

      final templates = await repo.watchAll('user1').first;
      expect(templates.length, 1);
      expect(templates.first.name, 'Workout A');
    });

    test('publishVersion creates version and increments header', () async {
      final id = await repo.create(
        name: 'Power Session',
        workoutType: WorkoutType.power,
        userId: 'user1',
      );

      final exercises = [
        ExercisePrescription(
          exerciseId: 'ex1',
          sortOrder: 0,
          mode: ExerciseMode.reps,
          exerciseName: 'Campus Board',
          sets: 5,
          reps: '5',
        ),
        ExercisePrescription(
          exerciseId: 'ex2',
          sortOrder: 1,
          mode: ExerciseMode.time,
          exerciseName: 'Limit Bouldering',
          durationSeconds: 300,
        ),
      ];

      final versionNum = await repo.publishVersion(
        templateId: id,
        exercises: exercises,
        userId: 'user1',
      );

      expect(versionNum, 1);

      // Header should be updated
      final header = await repo.getById(id);
      expect(header!.currentVersion, 1);
      expect(header.hasPublishedVersion, isTrue);

      // Version doc should exist
      final version = await repo.getVersion(id, 1);
      expect(version, isNotNull);
      expect(version!.versionNumber, 1);
      expect(version.exercises.length, 2);
      expect(version.exercises[0].exerciseName, 'Campus Board');
      expect(version.exercises[1].exerciseName, 'Limit Bouldering');
    });

    test('publishVersion increments from existing version', () async {
      final id = await repo.create(
        name: 'Evolving Workout',
        workoutType: WorkoutType.fullBody,
        userId: 'user1',
      );

      final v1 = await repo.publishVersion(
        templateId: id,
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
          ),
        ],
        userId: 'user1',
      );
      expect(v1, 1);

      final v2 = await repo.publishVersion(
        templateId: id,
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
          ),
          ExercisePrescription(
            exerciseId: 'ex2',
            sortOrder: 1,
            mode: ExerciseMode.time,
            durationSeconds: 60,
          ),
        ],
        userId: 'user1',
      );
      expect(v2, 2);

      final header = await repo.getById(id);
      expect(header!.currentVersion, 2);

      // Both versions should exist
      final version1 = await repo.getVersion(id, 1);
      expect(version1!.exercises.length, 1);
      final version2 = await repo.getVersion(id, 2);
      expect(version2!.exercises.length, 2);
    });

    test('getVersion returns null for non-existent version', () async {
      final id = await repo.create(
        name: 'No Versions',
        workoutType: WorkoutType.skill,
        userId: 'user1',
      );

      final version = await repo.getVersion(id, 1);
      expect(version, isNull);
    });

    test('prescription serialization round-trip preserves all fields',
        () async {
      final id = await repo.create(
        name: 'Full Prescription Test',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      await repo.publishVersion(
        templateId: id,
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
            exerciseName: 'Bench Press',
            sets: 4,
            reps: '6-8',
            weight: '185 lb',
            restSeconds: 120,
            notes: 'Pause at bottom',
          ),
        ],
        userId: 'user1',
      );

      final version = await repo.getVersion(id, 1);
      final p = version!.exercises.first;
      expect(p.exerciseId, 'ex1');
      expect(p.exerciseName, 'Bench Press');
      expect(p.mode, ExerciseMode.reps);
      expect(p.sets, 4);
      expect(p.reps, '6-8');
      expect(p.weight, '185 lb');
      expect(p.restSeconds, 120);
      expect(p.notes, 'Pause at bottom');
    });
  });

  group('WorkoutTemplateRepository ownership', () {
    test('update throws when caller is not creator', () async {
      final id = await repo.create(
        name: 'Owned Workout',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );

      expect(
        () => repo.update(
          id: id,
          name: 'Hijacked',
          workoutType: WorkoutType.pull,
          userId: 'not_the_creator',
        ),
        throwsStateError,
      );
    });

    test('softDelete throws when caller is not creator', () async {
      final id = await repo.create(
        name: 'Owned Workout',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );

      expect(
        () => repo.softDelete(id, 'not_the_creator'),
        throwsStateError,
      );
    });

    test('publishVersion throws when caller is not creator', () async {
      final id = await repo.create(
        name: 'Owned Workout',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );

      expect(
        () => repo.publishVersion(
          templateId: id,
          exercises: [],
          userId: 'not_the_creator',
        ),
        throwsStateError,
      );
    });
  });

  group('WorkoutTemplateRepository duplicate', () {
    test('duplicateTemplate creates new template with copied name', () async {
      final sourceId = await repo.create(
        name: 'Push Day',
        workoutType: WorkoutType.push,
        userId: 'user1',
      );

      final copyId = await repo.duplicateTemplate(
        sourceTemplateId: sourceId,
        userId: 'user1',
      );

      expect(copyId, isNot(sourceId));

      final copy = await repo.getById(copyId);
      expect(copy, isNotNull);
      expect(copy!.name, 'Push Day (Copy)');
      expect(copy.workoutType, WorkoutType.push);
      expect(copy.currentVersion, 0);
      expect(copy.hasPublishedVersion, isFalse);
    });

    test('duplicateTemplate throws for non-existent source', () async {
      expect(
        () => repo.duplicateTemplate(
          sourceTemplateId: 'nonexistent',
          userId: 'user1',
        ),
        throwsStateError,
      );
    });

    test('getLatestExercises returns exercises from latest version', () async {
      final id = await repo.create(
        name: 'Exercises Test',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      await repo.publishVersion(
        templateId: id,
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
            exerciseName: 'Bench Press',
            sets: 3,
            reps: '8-12',
          ),
        ],
        userId: 'user1',
      );

      final exercises = await repo.getLatestExercises(id);
      expect(exercises.length, 1);
      expect(exercises[0].exerciseName, 'Bench Press');
    });

    test('getLatestExercises returns empty for unpublished template',
        () async {
      final id = await repo.create(
        name: 'No Version',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      final exercises = await repo.getLatestExercises(id);
      expect(exercises, isEmpty);
    });
  });

  group('WorkoutTemplateRepository.isWorkoutReferenced', () {
    test('returns true when workout is in a published program', () async {
      final workoutId = await repo.create(
        name: 'Referenced Workout',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      // Create a program that references this workout
      final programRef = fakeFirestore.collection('programs').doc();
      await programRef.set({
        'name': 'My Program',
        'currentVersion': 1,
        'deletedAt': null,
        'ownerId': 'user1',
      });
      await programRef.collection('programVersions').doc('1').set({
        'versionNumber': 1,
        'workouts': [
          {'workoutTemplateId': workoutId, 'workoutTemplateVersion': 1, 'sortOrder': 0},
        ],
      });

      final referenced = await repo.isWorkoutReferenced(workoutId);
      expect(referenced, isTrue);
    });

    test('returns false when workout is not referenced', () async {
      final workoutId = await repo.create(
        name: 'Unreferenced Workout',
        workoutType: WorkoutType.lower,
        userId: 'user1',
      );

      final referenced = await repo.isWorkoutReferenced(workoutId);
      expect(referenced, isFalse);
    });

    test('returns false when referencing program is deleted', () async {
      final workoutId = await repo.create(
        name: 'Freed Workout',
        workoutType: WorkoutType.fullBody,
        userId: 'user1',
      );

      final programRef = fakeFirestore.collection('programs').doc();
      await programRef.set({
        'name': 'Deleted Program',
        'currentVersion': 1,
        'deletedAt': Timestamp.now(),
        'ownerId': 'user1',
      });
      await programRef.collection('programVersions').doc('1').set({
        'versionNumber': 1,
        'workouts': [
          {'workoutTemplateId': workoutId, 'workoutTemplateVersion': 1, 'sortOrder': 0},
        ],
      });

      final referenced = await repo.isWorkoutReferenced(workoutId);
      expect(referenced, isFalse);
    });
  });
}
