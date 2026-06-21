import 'package:flutter_test/flutter_test.dart';
import 'package:stage4/core/enums.dart';
import 'package:stage4/features/workouts/domain/workout_template.dart';

void main() {
  group('WorkoutTemplate', () {
    test('constructor and isDeleted', () {
      final template = WorkoutTemplate(
        id: 'wt1',
        name: 'Upper Pull Day',
        workoutType: WorkoutType.pull,
        currentVersion: 1,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );
      expect(template.id, 'wt1');
      expect(template.name, 'Upper Pull Day');
      expect(template.workoutType, WorkoutType.pull);
      expect(template.currentVersion, 1);
      expect(template.isDeleted, isFalse);
    });

    test('isDeleted true when deletedAt is set', () {
      final template = WorkoutTemplate(
        id: 'wt1',
        name: 'Upper Pull Day',
        workoutType: WorkoutType.pull,
        currentVersion: 1,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
        deletedAt: DateTime(2024, 2, 1),
        deletedBy: 'coach1',
      );
      expect(template.isDeleted, isTrue);
    });

    test('validate throws on empty id', () {
      final template = WorkoutTemplate(
        id: '',
        name: 'Upper Pull Day',
        workoutType: WorkoutType.pull,
        currentVersion: 1,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );
      expect(() => template.validate(), throwsArgumentError);
    });

    test('validate throws on currentVersion < 0', () {
      final template = WorkoutTemplate(
        id: 'wt1',
        name: 'Upper Pull Day',
        workoutType: WorkoutType.pull,
        currentVersion: -1,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );
      expect(() => template.validate(), throwsArgumentError);
    });

    test('validate succeeds for draft template with currentVersion 0', () {
      final template = WorkoutTemplate(
        id: 'wt1',
        name: 'Upper Pull Day',
        workoutType: WorkoutType.pull,
        currentVersion: 0,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );
      expect(() => template.validate(), returnsNormally);
      expect(template.hasPublishedVersion, isFalse);
    });

    test('validate throws on bad timestamp order', () {
      final template = WorkoutTemplate(
        id: 'wt1',
        name: 'Upper Pull Day',
        workoutType: WorkoutType.pull,
        currentVersion: 1,
        createdAt: DateTime(2024, 3, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => template.validate(), throwsArgumentError);
    });
  });

  group('WorkoutTemplateVersion', () {
    test('constructor with exercises', () {
      final version = WorkoutTemplateVersion(
        versionNumber: 1,
        publishedAt: DateTime(2024, 1, 1),
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
            sets: 3,
            reps: '8-12',
          ),
          ExercisePrescription(
            exerciseId: 'ex2',
            sortOrder: 1,
            mode: ExerciseMode.time,
            durationSeconds: 45,
            restSeconds: 60,
          ),
        ],
      );
      expect(version.versionNumber, 1);
      expect(version.exercises.length, 2);
      expect(version.childWorkouts, isEmpty);
    });

    test('validate throws on versionNumber < 1', () {
      final version = WorkoutTemplateVersion(
        versionNumber: 0,
        publishedAt: DateTime(2024, 1, 1),
        exercises: [],
      );
      expect(() => version.validate(), throwsArgumentError);
    });

    test('validate throws on duplicate exercise sortOrder', () {
      final version = WorkoutTemplateVersion(
        versionNumber: 1,
        publishedAt: DateTime(2024, 1, 1),
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
          ),
          ExercisePrescription(
            exerciseId: 'ex2',
            sortOrder: 0,
            mode: ExerciseMode.reps,
          ),
        ],
      );
      expect(() => version.validate(), throwsArgumentError);
    });

    test('validate succeeds with child workouts', () {
      final version = WorkoutTemplateVersion(
        versionNumber: 1,
        publishedAt: DateTime(2024, 1, 1),
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
          ),
        ],
        childWorkouts: [
          ChildWorkoutRef(
            workoutTemplateId: 'wt2',
            versionNumber: 1,
            sortOrder: 0,
          ),
        ],
      );
      expect(() => version.validate(), returnsNormally);
    });

    test('validate throws on duplicate child workout sortOrder', () {
      final version = WorkoutTemplateVersion(
        versionNumber: 1,
        publishedAt: DateTime(2024, 1, 1),
        exercises: [],
        childWorkouts: [
          ChildWorkoutRef(
            workoutTemplateId: 'wt2',
            versionNumber: 1,
            sortOrder: 0,
          ),
          ChildWorkoutRef(
            workoutTemplateId: 'wt3',
            versionNumber: 1,
            sortOrder: 0,
          ),
        ],
      );
      expect(() => version.validate(), throwsArgumentError);
    });
  });

  group('ExercisePrescription', () {
    test('reps mode with full prescription', () {
      final prescription = ExercisePrescription(
        exerciseId: 'ex1',
        sortOrder: 0,
        mode: ExerciseMode.reps,
        sets: 3,
        reps: '8-12',
        weight: '135 lb',
        restSeconds: 90,
        notes: 'Focus on form',
      );
      expect(prescription.mode, ExerciseMode.reps);
      expect(prescription.sets, 3);
      expect(prescription.reps, '8-12');
    });

    test('time mode with duration', () {
      final prescription = ExercisePrescription(
        exerciseId: 'ex1',
        sortOrder: 0,
        mode: ExerciseMode.time,
        sets: 4,
        durationSeconds: 45,
        restSeconds: 60,
      );
      expect(prescription.mode, ExerciseMode.time);
      expect(prescription.durationSeconds, 45);
    });

    test('amrap mode', () {
      final prescription = ExercisePrescription(
        exerciseId: 'ex1',
        sortOrder: 0,
        mode: ExerciseMode.amrap,
        durationSeconds: 60,
      );
      expect(prescription.mode, ExerciseMode.amrap);
    });

    test('validate throws on empty exerciseId', () {
      final prescription = ExercisePrescription(
        exerciseId: '',
        sortOrder: 0,
        mode: ExerciseMode.reps,
      );
      expect(() => prescription.validate(), throwsArgumentError);
    });

    test('validate throws on negative sortOrder', () {
      final prescription = ExercisePrescription(
        exerciseId: 'ex1',
        sortOrder: -1,
        mode: ExerciseMode.reps,
      );
      expect(() => prescription.validate(), throwsArgumentError);
    });

    test('validate throws on sets < 1', () {
      final prescription = ExercisePrescription(
        exerciseId: 'ex1',
        sortOrder: 0,
        mode: ExerciseMode.reps,
        sets: 0,
      );
      expect(() => prescription.validate(), throwsArgumentError);
    });

    test('validate throws on durationSeconds < 1', () {
      final prescription = ExercisePrescription(
        exerciseId: 'ex1',
        sortOrder: 0,
        mode: ExerciseMode.time,
        durationSeconds: 0,
      );
      expect(() => prescription.validate(), throwsArgumentError);
    });

    test('validate throws on negative restSeconds', () {
      final prescription = ExercisePrescription(
        exerciseId: 'ex1',
        sortOrder: 0,
        mode: ExerciseMode.reps,
        restSeconds: -1,
      );
      expect(() => prescription.validate(), throwsArgumentError);
    });
  });

  group('ChildWorkoutRef', () {
    test('constructor', () {
      final ref = ChildWorkoutRef(
        workoutTemplateId: 'wt2',
        versionNumber: 1,
        sortOrder: 0,
      );
      expect(ref.workoutTemplateId, 'wt2');
      expect(ref.versionNumber, 1);
    });

    test('validate throws on empty workoutTemplateId', () {
      final ref = ChildWorkoutRef(
        workoutTemplateId: '',
        versionNumber: 1,
        sortOrder: 0,
      );
      expect(() => ref.validate(), throwsArgumentError);
    });

    test('validate throws on versionNumber < 1', () {
      final ref = ChildWorkoutRef(
        workoutTemplateId: 'wt2',
        versionNumber: 0,
        sortOrder: 0,
      );
      expect(() => ref.validate(), throwsArgumentError);
    });
  });
}
