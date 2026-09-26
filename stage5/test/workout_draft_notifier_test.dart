import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

ExerciseSlot _slot(String id, String exercise, {int version = 2}) {
  return ExerciseSlot(
    slotId: id,
    exerciseId: exercise,
    exerciseVersion: version,
    exerciseName: exercise,
    sortOrder: 0,
    mode: ExerciseMode.reps,
    sets: 3,
    reps: '8',
  );
}

void main() {
  group('WorkoutDraftNotifier', () {
    test('revision changes only when draft contents change', () {
      final notifier = WorkoutDraftNotifier();
      expect(notifier.revision, 0);

      notifier.load(const []);
      expect(notifier.revision, 1);
      notifier.markSaved();
      expect(notifier.revision, 1);

      notifier.addExercise(
        blockId: 'block',
        slot: _slot('slot', 'squat'),
      );
      expect(notifier.revision, 2);
      notifier.undo();
      expect(notifier.revision, 3);
      notifier.clear();
      expect(notifier.revision, 4);
    });

    test('library add copies to a new stable block and slot', () {
      var sequence = 0;
      final notifier = WorkoutDraftNotifier(
        idGenerator: (prefix) => '$prefix-${sequence++}',
      );

      notifier.addLibraryExercise(
        exerciseId: 'squat',
        exerciseVersion: 4,
        exerciseName: 'Squat',
      );
      notifier.addLibraryExercise(
        exerciseId: 'squat',
        exerciseVersion: 4,
        exerciseName: 'Squat',
      );

      expect(notifier.state, hasLength(2));
      expect(
        notifier.state.map((block) => block.blockId).toSet(),
        hasLength(2),
      );
      expect(
        notifier.state
            .expand((block) => block.slots)
            .map((slot) => slot.slotId)
            .toSet(),
        hasLength(2),
      );
      expect(
        notifier.state
            .expand((block) => block.slots)
            .map((slot) => slot.exerciseVersion),
        everyElement(4),
      );
    });

    test('reorder and controls preserve IDs and pinned versions', () {
      final notifier = WorkoutDraftNotifier();
      notifier.addExercise(blockId: 'a', slot: _slot('slot-a', 'squat'));
      notifier.addExercise(
        blockId: 'b',
        slot: _slot('slot-b', 'bench', version: 5),
      );

      notifier.reorder(0, 2);
      expect(notifier.state.map((block) => block.blockId), ['b', 'a']);
      expect(notifier.state.first.slots.single.slotId, 'slot-b');
      expect(notifier.state.first.slots.single.exerciseVersion, 5);

      notifier.moveUp(1);
      expect(notifier.state.map((block) => block.blockId), ['a', 'b']);
    });

    test('compatible typed blocks accept and reorder copied slots', () {
      final notifier = WorkoutDraftNotifier();
      notifier.addTypedBlock(
        type: WorkoutBlockType.circuit,
        blockId: 'circuit',
        initialSlot: _slot('slot-a', 'pushup'),
      );
      notifier.addExerciseToBlock(
        targetBlockId: 'circuit',
        slot: _slot('slot-b', 'row'),
      );
      notifier.reorderSlot(blockId: 'circuit', oldIndex: 1, newIndex: 0);

      expect(notifier.state.single, isA<CircuitBlock>());
      expect(notifier.state.single.slots.map((slot) => slot.slotId), [
        'slot-b',
        'slot-a',
      ]);
      expect(() => notifier.state.single.validate(), returnsNormally);
    });

    test('single-slot blocks reject drops and duplicate IDs are blocked', () {
      final notifier = WorkoutDraftNotifier();
      notifier.addExercise(blockId: 'standard', slot: _slot('slot-a', 'squat'));

      expect(
        () => notifier.addExerciseToBlock(
          targetBlockId: 'standard',
          slot: _slot('slot-b', 'bench'),
        ),
        throwsStateError,
      );
      expect(
        () => notifier.addExercise(
          blockId: 'other',
          slot: _slot('slot-a', 'row'),
        ),
        throwsStateError,
      );
      expect(() => notifier.reorder(-1, 0), throwsRangeError);
    });

    test('duplicate uses new stable IDs and undo restores prior state', () {
      var sequence = 0;
      final notifier = WorkoutDraftNotifier(
        idGenerator: (prefix) => '$prefix-${sequence++}',
      );
      notifier.addExercise(blockId: 'original', slot: _slot('slot-a', 'squat'));
      notifier.markSaved();
      notifier.duplicateAt(0);

      expect(notifier.state, hasLength(2));
      expect(notifier.state[1].blockId, isNot('original'));
      expect(notifier.state[1].slots.single.slotId, isNot('slot-a'));
      expect(notifier.state[1].slots.single.exerciseVersion, 2);
      expect(notifier.canUndo, isTrue);

      notifier.undo();
      expect(notifier.state, hasLength(1));
      expect(notifier.state.single.blockId, 'original');
    });
  });
}
