import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_stage1/enums.dart';
import 'package:foundation_stage1/program.dart';

void main() {
  group('Program', () {
    test('constructor and convenience getters', () {
      final program = Program(
        id: 'prog1',
        name: '8-Week Strength',
        description: 'Progressive overload program',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );
      expect(program.id, 'prog1');
      expect(program.isDraft, isTrue);
      expect(program.isPublished, isFalse);
      expect(program.isAssignable, isTrue);
      expect(program.isDeleted, isFalse);
    });

    test('published assignable program', () {
      final program = Program(
        id: 'prog1',
        name: '8-Week Strength',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.published,
        currentVersion: 2,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 3, 1),
        updatedBy: 'coach1',
      );
      expect(program.isPublished, isTrue);
      expect(program.isAssignable, isTrue);
    });

    test('personal program is not assignable', () {
      final program = Program(
        id: 'prog2',
        name: 'My Training',
        ownerId: 'athlete1',
        type: ProgramType.personal,
        status: ProgramStatus.draft,
        currentVersion: 0,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'athlete1',
      );
      expect(program.isAssignable, isFalse);
    });

    test('validate throws on empty id', () {
      final program = Program(
        id: '',
        name: '8-Week Strength',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );
      expect(() => program.validate(), throwsArgumentError);
    });

    test('validate throws on empty ownerId', () {
      final program = Program(
        id: 'prog1',
        name: '8-Week Strength',
        ownerId: '',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );
      expect(() => program.validate(), throwsArgumentError);
    });

    test('validate throws on negative currentVersion', () {
      final program = Program(
        id: 'prog1',
        name: '8-Week Strength',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: -1,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );
      expect(() => program.validate(), throwsArgumentError);
    });

    test('validate throws on bad timestamp order', () {
      final program = Program(
        id: 'prog1',
        name: '8-Week Strength',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        createdAt: DateTime(2024, 3, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => program.validate(), throwsArgumentError);
    });

    test('program with typeWeightOverrides', () {
      final program = Program(
        id: 'prog1',
        name: 'Climbing Program',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        typeWeightOverrides: {WorkoutType.power: 3, WorkoutType.limit: 6},
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(program.hasCustomLoadWeights, isTrue);
      expect(program.typeWeightOverrides![WorkoutType.power], 3);
      expect(() => program.validate(), returnsNormally);
    });

    test('hasCustomLoadWeights false when no overrides', () {
      final program = Program(
        id: 'prog1',
        name: 'Default Program',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(program.hasCustomLoadWeights, isFalse);
    });

    test('validate throws on invalid typeWeightOverrides', () {
      final program = Program(
        id: 'prog1',
        name: 'Bad Weights',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        typeWeightOverrides: {WorkoutType.power: 0},
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => program.validate(), throwsArgumentError);
    });

    test('program with loadStrategyId', () {
      final program = Program(
        id: 'prog1',
        name: 'Custom Strategy',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        loadStrategyId: 'climbing_focused_v1',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(program.loadStrategyId, 'climbing_focused_v1');
      expect(() => program.validate(), returnsNormally);
    });
  });

  group('ProgramVersion', () {
    test('constructor with workouts', () {
      final version = ProgramVersion(
        versionNumber: 1,
        publishedAt: DateTime(2024, 2, 1),
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
          ProgramWorkoutRef(
            workoutTemplateId: 'wt2',
            workoutTemplateVersion: 2,
            sortOrder: 1,
          ),
        ],
        changeNote: 'Initial version',
      );
      expect(version.versionNumber, 1);
      expect(version.workouts.length, 2);
      expect(version.changeNote, 'Initial version');
    });

    test('validate throws on versionNumber < 1', () {
      final version = ProgramVersion(
        versionNumber: 0,
        publishedAt: DateTime(2024, 2, 1),
        workouts: [],
      );
      expect(() => version.validate(), throwsArgumentError);
    });

    test('validate throws on duplicate sortOrder', () {
      final version = ProgramVersion(
        versionNumber: 1,
        publishedAt: DateTime(2024, 2, 1),
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
          ProgramWorkoutRef(
            workoutTemplateId: 'wt2',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
        ],
      );
      expect(() => version.validate(), throwsArgumentError);
    });

    test('validate succeeds with empty workout list', () {
      final version = ProgramVersion(
        versionNumber: 1,
        publishedAt: DateTime(2024, 2, 1),
        workouts: [],
      );
      expect(() => version.validate(), returnsNormally);
    });
  });

  group('ProgramWorkoutRef', () {
    test('validate throws on empty workoutTemplateId', () {
      final ref = ProgramWorkoutRef(
        workoutTemplateId: '',
        workoutTemplateVersion: 1,
        sortOrder: 0,
      );
      expect(() => ref.validate(), throwsArgumentError);
    });

    test('validate throws on workoutTemplateVersion < 1', () {
      final ref = ProgramWorkoutRef(
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 0,
        sortOrder: 0,
      );
      expect(() => ref.validate(), throwsArgumentError);
    });

    test('validate throws on negative sortOrder', () {
      final ref = ProgramWorkoutRef(
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        sortOrder: -1,
      );
      expect(() => ref.validate(), throwsArgumentError);
    });
  });
}
