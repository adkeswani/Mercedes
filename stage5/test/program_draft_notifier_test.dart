import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';

ProgramScheduleEntry _entry({
  String workoutTemplateId = 'wt1',
  int dayOffset = 0,
  int sortOrder = 0,
}) {
  return ProgramScheduleEntry(
    workoutTemplateId: workoutTemplateId,
    workoutTemplateVersion: 1,
    dayOffset: dayOffset,
    sortOrder: sortOrder,
    workoutName: 'Workout',
  );
}

void main() {
  group('ProgramDraftNotifier', () {
    test('revision changes only when draft contents change', () {
      final notifier = ProgramDraftNotifier();
      expect(notifier.revision, 0);

      notifier.load(const []);
      expect(notifier.revision, 1);
      notifier.markSaved();
      expect(notifier.revision, 1);

      notifier.addWorkout(_entry());
      expect(notifier.revision, 2);
      notifier.undo();
      expect(notifier.revision, 3);
      notifier.clear();
      expect(notifier.revision, 4);
    });

    test('addWorkout appends entries', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry(workoutTemplateId: 'a'));
      notifier.addWorkout(_entry(workoutTemplateId: 'b', sortOrder: 1));
      expect(notifier.state.entries.length, 2);
      expect(notifier.state.entries[1].workoutTemplateId, 'b');
      expect(
        notifier.state.entries.map((entry) => entry.entryId).toSet(),
        hasLength(2),
      );
    });

    test('setDayOffset updates the targeted entry only', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry(workoutTemplateId: 'a', dayOffset: 0));
      notifier.addWorkout(
        _entry(workoutTemplateId: 'b', dayOffset: 0, sortOrder: 1),
      );
      notifier.setDayOffset(1, 7);
      expect(notifier.state.entries[0].dayOffset, 0);
      expect(notifier.state.entries[1].dayOffset, 7);
    });

    test('setDayOffset ignores out-of-range index', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry());
      notifier.setDayOffset(5, 3);
      expect(notifier.state.entries[0].dayOffset, 0);
    });

    test('setDayOffset ignores negative offset', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry(dayOffset: 2));
      notifier.setDayOffset(0, -1);
      expect(notifier.state.entries[0].dayOffset, 2);
    });

    test('addAll appends with contiguous sort orders', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry(workoutTemplateId: 'a'));
      notifier.addAll([
        _entry(workoutTemplateId: 'b', dayOffset: 7, sortOrder: 0),
        _entry(workoutTemplateId: 'c', dayOffset: 14, sortOrder: 0),
      ]);
      expect(notifier.state.entries.length, 3);
      expect(notifier.state.entries.map((e) => e.sortOrder).toList(), [
        0,
        1,
        2,
      ]);
      expect(notifier.state.entries[1].dayOffset, 7);
      expect(notifier.state.entries[2].dayOffset, 14);
    });

    test('removeAt reassigns sort orders and preserves dayOffset', () {
      final notifier = ProgramDraftNotifier();
      notifier.addAll([
        _entry(workoutTemplateId: 'a', dayOffset: 0),
        _entry(workoutTemplateId: 'b', dayOffset: 7),
        _entry(workoutTemplateId: 'c', dayOffset: 14),
      ]);
      notifier.removeAt(1);
      expect(notifier.state.entries.map((e) => e.workoutTemplateId).toList(), [
        'a',
        'c',
      ]);
      expect(notifier.state.entries.map((e) => e.sortOrder).toList(), [0, 1]);
      expect(notifier.state.entries[1].dayOffset, 14);
    });

    test('reorder and schedule edits preserve stable entry identity', () {
      final notifier = ProgramDraftNotifier();
      notifier.addAll([
        _entry(workoutTemplateId: 'a'),
        _entry(workoutTemplateId: 'b'),
      ]);
      final ids = notifier.state.entries.map((entry) => entry.entryId).toList();
      notifier.reorder(0, 2);
      notifier.setDayOffset(0, 10);
      expect(notifier.state.entries.map((entry) => entry.entryId), [
        ids[1],
        ids[0],
      ]);
    });

    test(
      'phases reorder without changing entry identity or pinned version',
      () {
        var sequence = 0;
        final notifier = ProgramDraftNotifier(
          idGenerator: (prefix) => '$prefix-${sequence++}',
        );
        notifier.addPhase('Base');
        notifier.addPhase('Build');
        final buildId = notifier.state.phases[1].phaseId;
        notifier.addWorkout(
          _entry(workoutTemplateId: 'a').copyWith(workoutTemplateVersion: 2),
          phaseId: buildId,
        );
        final entryId = notifier.state.entries.single.entryId;

        notifier.reorderPhase(1, 0);

        expect(notifier.state.phases.first.name, 'Build');
        expect(notifier.state.entries.single.entryId, entryId);
        expect(notifier.state.entries.single.workoutTemplateVersion, 2);
        expect(notifier.state.entries.single.phaseId, buildId);
      },
    );

    test('removing a phase preserves entries in the preceding phase', () {
      var sequence = 0;
      final notifier = ProgramDraftNotifier(
        idGenerator: (prefix) => '$prefix-${sequence++}',
      );
      notifier.addPhase('Base');
      notifier.addPhase('Build');
      final baseId = notifier.state.phases[0].phaseId;
      final buildId = notifier.state.phases[1].phaseId;
      notifier.addWorkout(_entry(), phaseId: buildId);

      notifier.removePhase(buildId);

      expect(notifier.state.entries.single.phaseId, baseId);
      expect(notifier.state.entries, hasLength(1));
    });

    test('duplicate gets a new stable ID and undo restores prior draft', () {
      var sequence = 0;
      final notifier = ProgramDraftNotifier(
        idGenerator: (prefix) => '$prefix-${sequence++}',
      );
      notifier.addWorkout(_entry());
      final originalId = notifier.state.entries.single.entryId;
      notifier.duplicateAt(0);
      expect(notifier.state.entries, hasLength(2));
      expect(notifier.state.entries[1].entryId, isNot(originalId));
      expect(notifier.state.entries[1].workoutTemplateVersion, 1);

      notifier.undo();
      expect(notifier.state.entries, hasLength(1));
      expect(notifier.state.entries.single.entryId, originalId);
    });

    test('invalid phase and index mutations fail explicitly', () {
      final notifier = ProgramDraftNotifier();
      expect(
        () => notifier.addWorkout(_entry(), phaseId: 'missing'),
        throwsStateError,
      );
      expect(() => notifier.reorder(0, 1), throwsRangeError);
    });
  });
}
