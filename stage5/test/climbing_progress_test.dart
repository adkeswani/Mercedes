import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'support/climbing_progress_fixtures.dart';

void main() {
  group('progress dates', () {
    for (final preset in ProgressPreset.values) {
      test('${preset.label} includes today and has a consecutive comparison',
          () {
        final range = preset.range(DateTime(2026, 11, 7, 14));
        expect(range.days, preset.days ?? 365);
        expect(range.end, DateTime(2026, 11, 7));
        expect(range.previous.days, range.days);
        expect(range.previous.endExclusive, range.start);
        expect(range.contains(DateTime(2026, 11, 7, 23, 59)), isTrue);
        expect(range.contains(DateTime(2026, 11, 8)), isFalse);
        expect(
            range.contains(
                range.start.subtract(const Duration(milliseconds: 1))),
            isFalse);
      });
    }
    test('leap-year range and calendar-day counts are inclusive', () {
      expect(ProgressPreset.year.range(DateTime(2024, 2, 29)).days, 366);
      expect(
          ProgressRange(start: DateTime(2026, 3, 7), end: DateTime(2026, 3, 9))
              .days,
          3);
      expect(
          ProgressRange(
                  start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 1))
              .days,
          1);
    });
    test('rejects reversed or more than 366 day ranges', () {
      expect(
          () => ProgressRange(start: DateTime(2026, 2), end: DateTime(2026, 1)),
          throwsArgumentError);
      expect(
          () => ProgressRange(start: DateTime(2025), end: DateTime(2026, 1, 2)),
          throwsArgumentError);
    });
    for (final preset in ProgressPreset.values) {
      test(
          '${preset.label} buckets cover the range without gaps or duplicate sessions',
          () {
        final range = preset.range(DateTime(2026, 11, 7));
        final report = ClimbingProgressReport(range: range, sessions: [
          progressSession(id: 'start', date: range.start),
          progressSession(id: 'end', date: range.end),
          progressSession(id: 'previous', date: range.previous.end),
        ]);
        expect(report.buckets.first.range.start, range.start);
        expect(report.buckets.last.range.end, range.end);
        expect(
            report.buckets
                .fold<int>(0, (sum, b) => sum + b.summary.sessionCount),
            2);
        for (var i = 1; i < report.buckets.length; i++) {
          expect(report.buckets[i - 1].range.endExclusive,
              report.buckets[i].range.start);
        }
        expect(report.previous.sessionCount, 1);
      });
    }
  });
  group('climbing interpretation', () {
    test(
        'workout selection recalculates both periods and never crosses athlete identity',
        () {
      final current = progressSession();
      final previous =
          progressSession(id: 'previous', date: DateTime(2026, 10, 5));
      final other = ClimbingSession.fromWorkout(
          progressInstance(id: current.instanceId, athlete: 'other'),
          progressVersion())!;
      final report = ClimbingProgressReport(
          range: ProgressPreset.month.range(DateTime(2026, 11, 7)),
          sessions: [current, previous, other]);
      final selected =
          report.excluding({current.selectionKey, previous.selectionKey});
      expect(selected.current.sessionCount, 1);
      expect(selected.current.sessions.single.athleteId, 'other');
      expect(selected.previous.sessionCount, 0);
      expect(selected.current.recordedClimbs, 9);
      expect(
          selected.buckets
              .fold<int>(0, (sum, bucket) => sum + bucket.summary.sessionCount),
          1);
    });
    test(
        'separates grades, counts whole rows, and never infers sends from counts',
        () {
      final summary = ClimbingSummary([progressSession()]);
      expect(summary.sessionCount, 1);
      expect(summary.recordedClimbs, 9);
      expect(summary.gradeCounts(ClimbingGradingSystem.vScale),
          {'V2': 3, 'V4': 1, 'V8': 4});
      expect(summary.gradeCounts(ClimbingGradingSystem.yds), {'5.11a': 1});
      expect(summary.highestSend(ClimbingGradingSystem.vScale), 'V4');
      expect(summary.highestSend(ClimbingGradingSystem.yds), '5.11a');
      expect(summary.incompleteSessions, 1);
      expect(summary.sessions.single.circuits.single.completedRows, 1);
      expect(summary.sessions.single.circuits.single.totalRows, 2);
    });
    test('canonical ordering is not lexical and ties do not add sends', () {
      final summary = ClimbingSummary([
        progressSession(id: 'v9', grade: 'V9'),
        progressSession(id: 'v10', grade: 'V10'),
        progressSession(id: 'unsent', grade: 'V14', sent: false),
      ]);
      expect(summary.highestSend(ClimbingGradingSystem.vScale), 'V10');
      expect(summary.gradeCounts(ClimbingGradingSystem.vScale).keys.toList(),
          ['V2', 'V8', 'V9', 'V10']);
    });
    test('optional free results and missing sends remain unrecorded', () {
      final session = progressSession(sent: null, freeCounts: false);
      expect(session.unrecordedBlocks, 3);
      expect(
          ClimbingSummary([session]).highestSend(ClimbingGradingSystem.vScale),
          isNull);
      expect(ClimbingSummary([]).recordedClimbs, isNull);
      expect(session.recordedClimbs, 4);
    });
    test('unrecorded route is not zero; a recorded unsent route is zero', () {
      WorkoutTemplateVersion routeVersion = WorkoutTemplateVersion(
          versionNumber: 1,
          publishedAt: DateTime(2026),
          blocks: [progressVersion().blocks.first]);
      for (final sent in [null, false]) {
        final instance = progressInstance(sent: sent);
        final session = ClimbingSession.fromWorkout(instance, routeVersion)!;
        expect(session.recordedClimbs, sent == null ? null : 0);
        expect(
            ClimbingSummary([session])
                .recordedFor(ClimbingGradingSystem.vScale),
            sent == null ? null : 0);
      }
    });
    test('legacy grades are excluded, not converted from colors', () {
      final version = WorkoutTemplateVersion(
          versionNumber: 1,
          publishedAt: DateTime(2026),
          blocks: [
            ClimbingRouteBlock(
                blockId: 'route',
                sortOrder: 0,
                route: progressVersion().blocks.first.slots.single,
                grade: 'V20',
                color: 'Blue')
          ]);
      final summary = ClimbingSummary(
          [ClimbingSession.fromWorkout(progressInstance(), version)!]);
      expect(summary.sessions.single.legacyRoutes, 1);
      expect(summary.highestSend(ClimbingGradingSystem.vScale), isNull);
      expect(summary.recordedClimbs, isNull);
    });
    test('completed time is used instead of scheduled date', () {
      expect(progressSession().date, DateTime(2026, 11, 6, 12));
    });
    test('circuit comparators keep changed pinned versions separate', () {
      expect(progressSession(version: 1).circuits.single.key,
          isNot(progressSession(version: 2).circuits.single.key));
    });
    test('standard workouts do not count as climbing sessions', () {
      final version = WorkoutTemplateVersion(
          versionNumber: 1,
          publishedAt: DateTime(2026),
          blocks: [
            StandardExerciseBlock(
                blockId: 'standard',
                sortOrder: 0,
                exercise: ExerciseSlot(
                    exerciseId: 'standard',
                    sortOrder: 0,
                    mode: ExerciseMode.reps))
          ]);
      expect(ClimbingSession.fromWorkout(progressInstance(), version), isNull);
    });
    test('mismatched row manifests fail instead of producing plausible totals',
        () {
      final instance = progressInstance();
      instance.actualsBySlot['circuit'] = ExerciseActual(
          slotId: 'circuit',
          exerciseId: climbingCircuitExerciseId,
          mode: ExerciseMode.reps,
          climbingType: 'climbingCircuit',
          circuitRows: const [
            ClimbingCircuitResultRow(rowId: 'wrong', completed: true)
          ]);
      expect(() => ClimbingSession.fromWorkout(instance, progressVersion()),
          throwsArgumentError);
    });
  });
}
