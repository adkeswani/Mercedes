import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'support/climbing_progress_fixtures.dart';

void main() {
  group('progress dates', () {
    for (final range in [
      ProgressPreset.week.range(DateTime(2026, 11, 7)),
      ProgressPreset.fortnight.range(DateTime(2026, 11, 7)),
      ProgressPreset.month.range(DateTime(2026, 11, 7)),
      ProgressPreset.year.range(DateTime(2024, 2, 29)),
      ProgressRange(start: DateTime(2026, 3, 7), end: DateTime(2026, 3, 9)),
      ProgressRange(start: DateTime(2026, 11, 7), end: DateTime(2026, 11, 7)),
    ]) {
      test(
          '${range.label} groups calendar weeks without gaps or duplicate completions',
          () {
        final report = ClimbingProgressReport(
          range: range,
          sessions: [
            for (var day = 0; day < range.days; day++)
              progressSession(
                id: '$day',
                date: DateTime(
                  range.start.year,
                  range.start.month,
                  range.start.day + day,
                ),
              ),
            progressSession(id: 'previous', date: range.previous.end),
          ],
        );
        final weeks = report.weeklyBuckets;
        expect(weeks.first.range.start, range.start);
        expect(weeks.last.range.end, range.end);
        expect(
          weeks.expand((week) => week.summary.sessions).length,
          range.days,
        );
        expect(
          weeks
              .expand((week) => week.summary.sessions)
              .map((session) => session.instanceId)
              .toSet()
              .length,
          range.days,
        );
        for (var index = 0; index < weeks.length; index++) {
          expect(weeks[index].range.days, lessThanOrEqualTo(7));
          if (index > 0) {
            expect(weeks[index].range.start.weekday, DateTime.monday);
            expect(
              weeks[index - 1].range.endExclusive,
              weeks[index].range.start,
            );
          }
        }
      });
    }
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
            range.start.subtract(const Duration(milliseconds: 1)),
          ),
          isFalse,
        );
      });
    }
    test('leap-year range and calendar-day counts are inclusive', () {
      expect(ProgressPreset.year.range(DateTime(2024, 2, 29)).days, 366);
      expect(
        ProgressRange(start: DateTime(2026, 3, 7), end: DateTime(2026, 3, 9))
            .days,
        3,
      );
      expect(
        ProgressRange(
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 11, 1),
        ).days,
        1,
      );
    });
    test('rejects reversed or more than 366 day ranges', () {
      expect(
        () => ProgressRange(start: DateTime(2026, 2), end: DateTime(2026, 1)),
        throwsArgumentError,
      );
      expect(
        () => ProgressRange(start: DateTime(2025), end: DateTime(2026, 1, 2)),
        throwsArgumentError,
      );
    });
    for (final preset in ProgressPreset.values) {
      test(
          '${preset.label} buckets cover the range without gaps or duplicate sessions',
          () {
        final range = preset.range(DateTime(2026, 11, 7));
        final report = ClimbingProgressReport(
          range: range,
          sessions: [
            progressSession(id: 'start', date: range.start),
            progressSession(id: 'end', date: range.end),
            progressSession(id: 'previous', date: range.previous.end),
          ],
        );
        expect(report.buckets.first.range.start, range.start);
        expect(report.buckets.last.range.end, range.end);
        expect(
          report.buckets.fold<int>(0, (sum, b) => sum + b.summary.sessionCount),
          2,
        );
        for (var i = 1; i < report.buckets.length; i++) {
          expect(
            report.buckets[i - 1].range.endExclusive,
            report.buckets[i].range.start,
          );
        }
        expect(report.previous.sessionCount, 1);
      });
    }
  });
  group('climbing interpretation', () {
    test(
        'groups by program IDs, not names, with tri-state selection across both periods',
        () {
      final first =
          progressSession(id: 'first', programId: 'one', programName: 'Plan');
      final previous = progressSession(
        id: 'previous',
        programId: 'one',
        programName: 'Plan',
        date: DateTime(2026, 10, 5),
      );
      final report = ClimbingProgressReport(
        range: ProgressPreset.month.range(DateTime(2026, 11, 7)),
        sessions: [
          first,
          previous,
          progressSession(
            id: 'different',
            programId: 'two',
            programName: 'Plan',
          ),
          progressSession(id: 'independent'),
        ],
      );
      final groups = report.workoutGroups;
      expect(
        groups.map((group) => group.key).toList(),
        ['program:one', 'program:two', 'independent'],
      );
      expect(groups.first.selectionValue({}), isTrue);
      expect(groups.first.selectionValue({first.selectionKey}), isNull);
      expect(
        groups.first
            .selectionValue({first.selectionKey, previous.selectionKey}),
        isFalse,
      );
      expect(
        groups.first.selectionValue({('other', first.instanceId)}),
        isTrue,
      );
      expect(progressProgramId(progressInstance()), isNull);
      expect(
        progressProgramId(progressInstance(programInstanceId: 'assignment')),
        'program',
      );
      expect(progressProgramId(progressInstance(programVersion: 1)), 'program');
    });
    test(
        'workout selection recalculates both periods and never crosses athlete identity',
        () {
      final current = progressSession();
      final previous =
          progressSession(id: 'previous', date: DateTime(2026, 10, 5));
      final other = ClimbingSession.fromWorkout(
        progressInstance(id: current.instanceId, athlete: 'other'),
        progressVersion(),
      )!;
      final report = ClimbingProgressReport(
        range: ProgressPreset.month.range(DateTime(2026, 11, 7)),
        sessions: [current, previous, other],
      );
      final selected =
          report.excluding({current.selectionKey, previous.selectionKey});
      expect(selected.current.sessionCount, 1);
      expect(selected.current.sessions.single.athleteId, 'other');
      expect(selected.previous.sessionCount, 0);
      expect(selected.current.recordedClimbs, 9);
      expect(
        selected.buckets
            .fold<int>(0, (sum, bucket) => sum + bucket.summary.sessionCount),
        1,
      );
    });
    test(
        'separates grades, counts whole rows, and never infers sends from counts',
        () {
      final summary = ClimbingSummary([progressSession()]);
      expect(summary.sessionCount, 1);
      expect(summary.recordedClimbs, 9);
      expect(
        summary.gradeCounts(ClimbingGradingSystem.vScale),
        {'V2': 3, 'V4': 1, 'V8': 4},
      );
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
      expect(
        summary.gradeCounts(ClimbingGradingSystem.vScale).keys.toList(),
        ['V2', 'V8', 'V9', 'V10', 'V14'],
      );
    });
    test('optional free results and missing sends remain unrecorded', () {
      final session = progressSession(sent: null, freeCounts: false);
      expect(session.unrecordedBlocks, 3);
      expect(
        ClimbingSummary([session]).highestSend(ClimbingGradingSystem.vScale),
        isNull,
      );
      expect(ClimbingSummary([]).recordedClimbs, isNull);
      expect(session.recordedClimbs, 4);
    });
    test(
        'per-climb free results count once, include sends, and ignore legacy aggregates',
        () {
      final actual = ExerciseActual(
        slotId: 'free',
        exerciseId: freeClimbingExerciseId,
        mode: ExerciseMode.reps,
        climbingType: 'freeClimbing',
        freeRows: const [
          FreeClimbingResultRow(
              rowId: 'sent',
              gradingSystem: ClimbingGradingSystem.vScale,
              grade: 'V6',
              attempts: 3,
              sent: true),
          FreeClimbingResultRow(
              rowId: 'unsent',
              gradingSystem: ClimbingGradingSystem.vScale,
              grade: 'V8',
              attempts: 5,
              sent: false),
          FreeClimbingResultRow(
              rowId: 'legacy',
              gradingSystem: ClimbingGradingSystem.vScale,
              grade: 'V10',
              climbs: 9),
        ],
      );
      final instance = progressInstance(actuals: [actual]);
      final version = WorkoutTemplateVersion(
          versionNumber: 1,
          publishedAt: DateTime(2026),
          blocks: [progressVersion().blocks.last]);
      final session = ClimbingSession.fromWorkout(instance, version)!;
      expect(session.recordedClimbs, 2);
      expect(session.routes.map((route) => route.attempts), [3, 5]);
      final summary = ClimbingSummary([session]);
      expect(summary.highestGrade(ClimbingGradingSystem.vScale), 'V8');
      expect(summary.highestSend(ClimbingGradingSystem.vScale), 'V6');
      expect(summary.gradeCounts(ClimbingGradingSystem.vScale),
          {'V6': 1, 'V8': 1});
      final filtered = ClimbingSummary([session.sentOnly()]);
      expect(filtered.recordedClimbs, 1);
      expect(filtered.highestGrade(ClimbingGradingSystem.vScale), 'V6');
      expect(filtered.gradeCounts(ClimbingGradingSystem.vScale), {'V6': 1});
    });
    test('unsent routes count once by default and zero with sent-only filter',
        () {
      WorkoutTemplateVersion routeVersion = WorkoutTemplateVersion(
        versionNumber: 1,
        publishedAt: DateTime(2026),
        blocks: [progressVersion().blocks.first],
      );
      for (final sent in [null, false]) {
        final instance = progressInstance(sent: sent);
        final session = ClimbingSession.fromWorkout(instance, routeVersion)!;
        expect(session.recordedClimbs, sent == null ? null : 1);
        expect(
          ClimbingSummary([session]).recordedFor(ClimbingGradingSystem.vScale),
          sent == null ? null : 1,
        );
        expect(session.sentOnly().recordedClimbs, sent == null ? null : 0);
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
            color: 'Blue',
          ),
        ],
      );
      final summary = ClimbingSummary(
        [ClimbingSession.fromWorkout(progressInstance(), version)!],
      );
      expect(summary.sessions.single.legacyRoutes, 1);
      expect(summary.highestSend(ClimbingGradingSystem.vScale), isNull);
      expect(summary.recordedClimbs, isNull);
    });
    test('completed time is used instead of scheduled date', () {
      expect(progressSession().date, DateTime(2026, 11, 6, 12));
    });
    test('circuit comparators keep changed pinned versions separate', () {
      expect(
        progressSession(version: 1).circuits.single.key,
        isNot(progressSession(version: 2).circuits.single.key),
      );
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
              mode: ExerciseMode.reps,
            ),
          ),
        ],
      );
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
          ClimbingCircuitResultRow(rowId: 'wrong', completed: true),
        ],
      );
      expect(
        () => ClimbingSession.fromWorkout(instance, progressVersion()),
        throwsArgumentError,
      );
    });
  });
}
