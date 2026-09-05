import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

ExerciseSlot slot(
  String slotId,
  String exerciseId,
  int sortOrder, {
  ExerciseMode mode = ExerciseMode.reps,
}) {
  return ExerciseSlot(
    slotId: slotId,
    exerciseId: exerciseId,
    exerciseVersion: 2,
    sortOrder: sortOrder,
    mode: mode,
    sets: 3,
    reps: '8-12',
  );
}

void main() {
  group('typed workout blocks', () {
    test('standard exercise preserves the stable slot and pinned version', () {
      final block = StandardExerciseBlock(
        blockId: 'standard-1',
        sortOrder: 0,
        exercise: slot('slot-1', 'squat', 0),
      );

      expect(block.type, WorkoutBlockType.standardExercise);
      expect(block.exercise.slotId, 'slot-1');
      expect(block.exercise.exerciseId, 'squat');
      expect(block.exercise.exerciseVersion, 2);
      expect(() => block.validate(), returnsNormally);
    });

    test('timed interval represents rounds, work, rest, and ordered slots', () {
      final block = TimedIntervalBlock(
        blockId: 'interval-1',
        sortOrder: 0,
        slots: [
          slot('slot-1', 'bike', 0, mode: ExerciseMode.time),
          slot('slot-2', 'rest-position', 1, mode: ExerciseMode.time),
        ],
        rounds: 8,
        workSeconds: 30,
        restSeconds: 90,
      );

      expect(block.type, WorkoutBlockType.timedInterval);
      expect(block.rounds, 8);
      expect(block.workSeconds, 30);
      expect(block.restSeconds, 90);
      expect(() => block.validate(), returnsNormally);
    });

    test('circuit groups repeated rounds of multiple stable slots', () {
      final block = CircuitBlock(
        blockId: 'circuit-1',
        sortOrder: 1,
        slots: [
          slot('slot-pushup', 'pushup', 0),
          slot('slot-row', 'row', 1),
        ],
        rounds: 4,
        restBetweenRoundsSeconds: 60,
      );

      expect(block.type, WorkoutBlockType.circuit);
      expect(block.slots.map((item) => item.slotId), [
        'slot-pushup',
        'slot-row',
      ]);
      expect(() => block.validate(), returnsNormally);
    });

    test('climbing route records grade, color, and target attempts', () {
      final block = ClimbingRouteBlock(
        blockId: 'route-1',
        sortOrder: 2,
        route: slot('slot-route', 'route-exercise', 0),
        grade: 'V6',
        color: 'Blue',
        targetAttempts: 3,
      );

      expect(block.type, WorkoutBlockType.climbingRoute);
      expect(block.grade, 'V6');
      expect(block.color, 'Blue');
      expect(block.targetAttempts, 3);
      expect(() => block.validate(), returnsNormally);
    });

    test('version rejects duplicate slot IDs across different blocks', () {
      final version = WorkoutTemplateVersion(
        versionNumber: 1,
        publishedAt: DateTime(2026, 9, 1),
        blocks: [
          StandardExerciseBlock(
            blockId: 'block-1',
            sortOrder: 0,
            exercise: slot('same-slot', 'squat', 0),
          ),
          StandardExerciseBlock(
            blockId: 'block-2',
            sortOrder: 1,
            exercise: slot('same-slot', 'bench', 0),
          ),
        ],
      );

      expect(() => version.validate(), throwsArgumentError);
    });

    test('legacy flat prescriptions receive deterministic stable IDs', () {
      final version = WorkoutTemplateVersion(
        versionNumber: 1,
        publishedAt: DateTime(2026, 9, 1),
        exercises: [
          ExerciseSlot(
            exerciseId: 'same-exercise',
            sortOrder: 0,
            mode: ExerciseMode.reps,
          ),
          ExerciseSlot(
            exerciseId: 'same-exercise',
            sortOrder: 1,
            mode: ExerciseMode.amrap,
          ),
        ],
      );

      expect(version.blocks.map((block) => block.blockId), [
        'legacy-block-0',
        'legacy-block-1',
      ]);
      expect(version.exerciseSlots.map((item) => item.slotId), [
        'legacy-slot-0',
        'legacy-slot-1',
      ]);
    });

    test('invalid interval and climbing payloads are rejected', () {
      expect(
        () => TimedIntervalBlock(
          blockId: 'interval',
          sortOrder: 0,
          slots: [slot('slot-1', 'bike', 0)],
          rounds: 0,
          workSeconds: 30,
          restSeconds: 0,
        ).validate(),
        throwsArgumentError,
      );
      expect(
        () => ClimbingRouteBlock(
          blockId: 'route',
          sortOrder: 0,
          route: slot('slot-1', 'route', 0),
          grade: '',
          color: 'Red',
        ).validate(),
        throwsArgumentError,
      );
    });
  });
}
