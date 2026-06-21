import 'package:flutter_test/flutter_test.dart';
import 'package:stage4/features/programs/domain/program.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';

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
    test('addWorkout appends entries', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry(workoutTemplateId: 'a'));
      notifier.addWorkout(_entry(workoutTemplateId: 'b', sortOrder: 1));
      expect(notifier.state.length, 2);
      expect(notifier.state[1].workoutTemplateId, 'b');
    });

    test('setDayOffset updates the targeted entry only', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry(workoutTemplateId: 'a', dayOffset: 0));
      notifier.addWorkout(
        _entry(workoutTemplateId: 'b', dayOffset: 0, sortOrder: 1),
      );
      notifier.setDayOffset(1, 7);
      expect(notifier.state[0].dayOffset, 0);
      expect(notifier.state[1].dayOffset, 7);
    });

    test('setDayOffset ignores out-of-range index', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry());
      notifier.setDayOffset(5, 3);
      expect(notifier.state[0].dayOffset, 0);
    });

    test('setDayOffset ignores negative offset', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry(dayOffset: 2));
      notifier.setDayOffset(0, -1);
      expect(notifier.state[0].dayOffset, 2);
    });

    test('addAll appends with contiguous sort orders', () {
      final notifier = ProgramDraftNotifier();
      notifier.addWorkout(_entry(workoutTemplateId: 'a'));
      notifier.addAll([
        _entry(workoutTemplateId: 'b', dayOffset: 7, sortOrder: 0),
        _entry(workoutTemplateId: 'c', dayOffset: 14, sortOrder: 0),
      ]);
      expect(notifier.state.length, 3);
      expect(notifier.state.map((e) => e.sortOrder).toList(), [0, 1, 2]);
      expect(notifier.state[1].dayOffset, 7);
      expect(notifier.state[2].dayOffset, 14);
    });

    test('removeAt reassigns sort orders and preserves dayOffset', () {
      final notifier = ProgramDraftNotifier();
      notifier.addAll([
        _entry(workoutTemplateId: 'a', dayOffset: 0),
        _entry(workoutTemplateId: 'b', dayOffset: 7),
        _entry(workoutTemplateId: 'c', dayOffset: 14),
      ]);
      notifier.removeAt(1);
      expect(notifier.state.map((e) => e.workoutTemplateId).toList(),
          ['a', 'c']);
      expect(notifier.state.map((e) => e.sortOrder).toList(), [0, 1]);
      expect(notifier.state[1].dayOffset, 14);
    });
  });
}
