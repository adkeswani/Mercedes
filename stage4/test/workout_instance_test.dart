import 'package:flutter_test/flutter_test.dart';
import 'package:stage4/core/enums.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';

void main() {
  group('WorkoutInstance', () {
    test('constructor defaults for scheduled instance', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.scheduled,
        workoutType: WorkoutType.pull,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
      );
      expect(instance.isScheduled, isTrue);
      expect(instance.isCompleted, isFalse);
      expect(instance.isMissed, isFalse);
      expect(instance.loadModelVersion, 1);
      expect(instance.isRecurrenceRoot, isFalse);
      expect(instance.actuals, isEmpty);
    });

    test('completed instance with RPE and duration', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.completed,
        completedAt: DateTime(2026, 4, 15, 18, 30),
        rpe: 7,
        durationMinutes: 55,
        loadPoints: 20.0,
        workoutType: WorkoutType.pull,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 15, 18, 30),
      );
      expect(instance.isCompleted, isTrue);
      expect(instance.rpe, 7);
      expect(instance.durationMinutes, 55);
      expect(instance.loadPoints, 20.0);
    });

    test('validate throws on empty id', () {
      final instance = _makeScheduledInstance(id: '');
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws on empty programId', () {
      final instance = _makeScheduledInstance(programId: '');
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws on invalid date format', () {
      final instance = _makeScheduledInstance(scheduledDate: '2026/04/15');
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws on workoutTemplateVersion < 1', () {
      final instance = _makeScheduledInstance(workoutTemplateVersion: 0);
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws when completed without rpe', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.completed,
        completedAt: DateTime(2026, 4, 15),
        durationMinutes: 55,
        workoutType: WorkoutType.pull,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 15),
      );
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws when completed without durationMinutes', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.completed,
        completedAt: DateTime(2026, 4, 15),
        rpe: 7,
        workoutType: WorkoutType.pull,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 15),
      );
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws when completed without completedAt', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.completed,
        rpe: 7,
        durationMinutes: 55,
        workoutType: WorkoutType.pull,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 15),
      );
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws on rpe out of range', () {
      final instance = _makeScheduledInstance(rpe: 11);
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws on rpe below 1', () {
      final instance = _makeScheduledInstance(rpe: 0);
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws on negative durationMinutes', () {
      final instance = _makeScheduledInstance(durationMinutes: -1);
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid scheduled instance', () {
      final instance = _makeScheduledInstance();
      expect(() => instance.validate(), returnsNormally);
    });

    test('instance with actuals', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.completed,
        completedAt: DateTime(2026, 4, 15),
        rpe: 7,
        durationMinutes: 55,
        workoutType: WorkoutType.pull,
        actuals: [
          ExerciseActual(
            exerciseId: 'ex1',
            mode: ExerciseMode.reps,
            sets: 3,
            reps: '10',
            weight: '135 lb',
          ),
        ],
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 15),
      );
      expect(instance.actuals.length, 1);
      expect(() => instance.validate(), returnsNormally);
    });

    test('effectiveLoadPoints returns computed when no override', () {
      final instance = _makeScheduledInstance();
      expect(instance.loadPoints, isNull);
      expect(instance.loadPointsOverride, isNull);
      expect(instance.effectiveLoadPoints, isNull);
      expect(instance.isLoadOverridden, isFalse);
    });

    test('effectiveLoadPoints returns override when set', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.completed,
        completedAt: DateTime(2026, 4, 15),
        rpe: 7,
        durationMinutes: 55,
        loadPoints: 12.0,
        loadPointsOverride: 8.0,
        loadPointsOverriddenBy: 'coach1',
        loadPointsOverriddenAt: DateTime(2026, 4, 16),
        workoutType: WorkoutType.pull,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 15),
      );
      expect(instance.effectiveLoadPoints, 8.0);
      expect(instance.isLoadOverridden, isTrue);
      expect(instance.loadPointsOverriddenBy, 'coach1');
      // Computed value is preserved
      expect(instance.loadPoints, 12.0);
    });

    test('validate throws when override set without overriddenBy', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.scheduled,
        loadPointsOverride: 8.0,
        loadPointsOverriddenAt: DateTime(2026, 4, 16),
        workoutType: WorkoutType.pull,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
      );
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('validate throws when override set without overriddenAt', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.scheduled,
        loadPointsOverride: 8.0,
        loadPointsOverriddenBy: 'coach1',
        workoutType: WorkoutType.pull,
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
      );
      expect(() => instance.validate(), throwsArgumentError);
    });

    test('loadStrategyId is stored on instance', () {
      final instance = WorkoutInstance(
        id: 'wi1',
        programId: 'prog1',
        athleteId: 'athlete1',
        workoutTemplateId: 'wt1',
        workoutTemplateVersion: 1,
        scheduledDate: '2026-04-15',
        assignedBy: 'coach1',
        assignedAt: DateTime(2026, 4, 1),
        status: WorkoutInstanceStatus.scheduled,
        workoutType: WorkoutType.pull,
        loadStrategyId: 'climbing_focused_v1',
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
      );
      expect(instance.loadStrategyId, 'climbing_focused_v1');
    });
  });

  group('ExerciseActual', () {
    test('constructor', () {
      final actual = ExerciseActual(
        exerciseId: 'ex1',
        mode: ExerciseMode.reps,
        sets: 3,
        reps: '10',
        weight: '135 lb',
        restSeconds: 90,
        notes: 'Felt strong',
      );
      expect(actual.exerciseId, 'ex1');
      expect(actual.mode, ExerciseMode.reps);
    });

    test('validate throws on empty exerciseId', () {
      final actual = ExerciseActual(
        exerciseId: '',
        mode: ExerciseMode.reps,
      );
      expect(() => actual.validate(), throwsArgumentError);
    });

    test('validate throws on sets < 1', () {
      final actual = ExerciseActual(
        exerciseId: 'ex1',
        mode: ExerciseMode.reps,
        sets: 0,
      );
      expect(() => actual.validate(), throwsArgumentError);
    });

    test('validate throws on negative durationSeconds', () {
      final actual = ExerciseActual(
        exerciseId: 'ex1',
        mode: ExerciseMode.time,
        durationSeconds: -1,
      );
      expect(() => actual.validate(), throwsArgumentError);
    });
  });

  group('Recurrence', () {
    test('weekly recurrence', () {
      final recurrence = Recurrence(
        pattern: RecurrencePattern.weekly,
        daysOfWeek: [1, 3, 5],
        endDate: '2026-05-24',
      );
      expect(recurrence.pattern, RecurrencePattern.weekly);
      expect(recurrence.daysOfWeek, [1, 3, 5]);
    });

    test('validate throws on empty endDate', () {
      final recurrence = Recurrence(
        pattern: RecurrencePattern.weekly,
        endDate: '',
      );
      expect(() => recurrence.validate(), throwsArgumentError);
    });

    test('validate throws on invalid endDate format', () {
      final recurrence = Recurrence(
        pattern: RecurrencePattern.weekly,
        endDate: '2026/05/24',
      );
      expect(() => recurrence.validate(), throwsArgumentError);
    });

    test('validate throws on daysOfWeek out of range', () {
      final recurrence = Recurrence(
        pattern: RecurrencePattern.weekly,
        daysOfWeek: [0, 3],
        endDate: '2026-05-24',
      );
      expect(() => recurrence.validate(), throwsArgumentError);
    });

    test('validate throws on daysOfWeek > 7', () {
      final recurrence = Recurrence(
        pattern: RecurrencePattern.weekly,
        daysOfWeek: [1, 8],
        endDate: '2026-05-24',
      );
      expect(() => recurrence.validate(), throwsArgumentError);
    });

    test('validate throws on custom without intervalDays', () {
      final recurrence = Recurrence(
        pattern: RecurrencePattern.custom,
        endDate: '2026-05-24',
      );
      expect(() => recurrence.validate(), throwsArgumentError);
    });

    test('validate throws on intervalDays < 1', () {
      final recurrence = Recurrence(
        pattern: RecurrencePattern.custom,
        intervalDays: 0,
        endDate: '2026-05-24',
      );
      expect(() => recurrence.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid custom recurrence', () {
      final recurrence = Recurrence(
        pattern: RecurrencePattern.custom,
        intervalDays: 3,
        endDate: '2026-05-24',
      );
      expect(() => recurrence.validate(), returnsNormally);
    });
  });

  group('expandRecurrence', () {
    test('weekly on Mon/Wed/Fri for 2 weeks', () {
      final dates = expandRecurrence(
        startDate: '2026-06-15', // Monday
        pattern: RecurrencePattern.weekly,
        endDate: '2026-06-28', // Sunday 2 weeks later
        daysOfWeek: [1, 3, 5], // Mon, Wed, Fri
      );
      expect(dates, [
        '2026-06-15', // Mon
        '2026-06-17', // Wed
        '2026-06-19', // Fri
        '2026-06-22', // Mon
        '2026-06-24', // Wed
        '2026-06-26', // Fri
      ]);
    });

    test('weekly defaults to start date weekday when daysOfWeek is null', () {
      final dates = expandRecurrence(
        startDate: '2026-06-17', // Wednesday
        pattern: RecurrencePattern.weekly,
        endDate: '2026-07-01',
      );
      expect(dates, [
        '2026-06-17', // Wed
        '2026-06-24', // Wed
        '2026-07-01', // Wed
      ]);
    });

    test('weekly defaults when daysOfWeek is empty', () {
      final dates = expandRecurrence(
        startDate: '2026-06-17', // Wednesday
        pattern: RecurrencePattern.weekly,
        endDate: '2026-07-01',
        daysOfWeek: [],
      );
      expect(dates, [
        '2026-06-17',
        '2026-06-24',
        '2026-07-01',
      ]);
    });

    test('biweekly on Tuesday for 6 weeks', () {
      final dates = expandRecurrence(
        startDate: '2026-06-16', // Tuesday
        pattern: RecurrencePattern.biweekly,
        endDate: '2026-07-28',
        daysOfWeek: [2], // Tuesday
      );
      expect(dates, [
        '2026-06-16',
        '2026-06-30',
        '2026-07-14',
        '2026-07-28',
      ]);
    });

    test('custom every 3 days', () {
      final dates = expandRecurrence(
        startDate: '2026-06-15',
        pattern: RecurrencePattern.custom,
        endDate: '2026-06-24',
        intervalDays: 3,
      );
      expect(dates, [
        '2026-06-15',
        '2026-06-18',
        '2026-06-21',
        '2026-06-24',
      ]);
    });

    test('custom every day', () {
      final dates = expandRecurrence(
        startDate: '2026-06-15',
        pattern: RecurrencePattern.custom,
        endDate: '2026-06-17',
        intervalDays: 1,
      );
      expect(dates, ['2026-06-15', '2026-06-16', '2026-06-17']);
    });

    test('returns empty when end is before start', () {
      final dates = expandRecurrence(
        startDate: '2026-06-20',
        pattern: RecurrencePattern.weekly,
        endDate: '2026-06-15',
        daysOfWeek: [1],
      );
      expect(dates, isEmpty);
    });

    test('returns empty for custom with null intervalDays', () {
      final dates = expandRecurrence(
        startDate: '2026-06-15',
        pattern: RecurrencePattern.custom,
        endDate: '2026-06-20',
      );
      expect(dates, isEmpty);
    });

    test('single day range returns one date for matching day', () {
      final dates = expandRecurrence(
        startDate: '2026-06-15', // Monday
        pattern: RecurrencePattern.weekly,
        endDate: '2026-06-15',
        daysOfWeek: [1], // Monday
      );
      expect(dates, ['2026-06-15']);
    });

    test('caps at maxInstances', () {
      // Daily for 2 years would be ~730 days, cap at 364
      final dates = expandRecurrence(
        startDate: '2026-01-01',
        pattern: RecurrencePattern.custom,
        endDate: '2027-12-31',
        intervalDays: 1,
      );
      expect(dates.length, Recurrence.maxInstances);
    });

    test('weekly skips start week days before start date', () {
      // Start is Wednesday, ask for Mon/Wed/Fri
      // Should NOT include the Monday before start
      final dates = expandRecurrence(
        startDate: '2026-06-17', // Wednesday
        pattern: RecurrencePattern.weekly,
        endDate: '2026-06-22',
        daysOfWeek: [1, 3, 5], // Mon, Wed, Fri
      );
      expect(dates, [
        '2026-06-17', // Wed
        '2026-06-19', // Fri
        '2026-06-22', // Mon next week
      ]);
    });
  });

  group('addDays', () {
    test('adds zero days returns same date', () {
      expect(addDays('2026-06-01', 0), '2026-06-01');
    });

    test('adds days within a month', () {
      expect(addDays('2026-06-01', 3), '2026-06-04');
    });

    test('rolls across a month boundary', () {
      expect(addDays('2026-06-29', 5), '2026-07-04');
    });

    test('rolls across a year boundary', () {
      expect(addDays('2026-12-30', 3), '2027-01-02');
    });

    test('handles a leap day', () {
      expect(addDays('2028-02-28', 1), '2028-02-29');
    });
  });
}

/// Helper to create a minimal valid scheduled instance with overrides.
WorkoutInstance _makeScheduledInstance({
  String id = 'wi1',
  String programId = 'prog1',
  String athleteId = 'athlete1',
  String workoutTemplateId = 'wt1',
  int workoutTemplateVersion = 1,
  String scheduledDate = '2026-04-15',
  String assignedBy = 'coach1',
  int? rpe,
  int? durationMinutes,
}) {
  return WorkoutInstance(
    id: id,
    programId: programId,
    athleteId: athleteId,
    workoutTemplateId: workoutTemplateId,
    workoutTemplateVersion: workoutTemplateVersion,
    scheduledDate: scheduledDate,
    assignedBy: assignedBy,
    assignedAt: DateTime(2026, 4, 1),
    status: WorkoutInstanceStatus.scheduled,
    rpe: rpe,
    durationMinutes: durationMinutes,
    workoutType: WorkoutType.pull,
    createdAt: DateTime(2026, 4, 1),
    updatedAt: DateTime(2026, 4, 1),
  );
}
