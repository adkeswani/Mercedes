import 'package:stage5/features/workouts/data/workout_local_day.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

enum ProgressPreset {
  week('Last 7 days', 7),
  fortnight('Last 14 days', 14),
  month('Last 30 days', 30),
  year('Last 12 months', null);

  const ProgressPreset(this.label, this.days);
  final String label;
  final int? days;

  ProgressRange range(DateTime now) => ProgressRange(
        start: days == null
            ? _yearStart(now)
            : DateTime(now.year, now.month, now.day - days! + 1),
        end: now,
      );

  static DateTime _yearStart(DateTime now) {
    final exclusive = DateTime(now.year, now.month, now.day + 1);
    final lastDay = DateTime(exclusive.year - 1, exclusive.month + 1, 0).day;
    return DateTime(
      exclusive.year - 1,
      exclusive.month,
      exclusive.day > lastDay ? lastDay : exclusive.day,
    );
  }
}

class ProgressRange {
  ProgressRange({required DateTime start, required DateTime end})
      : start = DateTime(start.year, start.month, start.day),
        end = DateTime(end.year, end.month, end.day) {
    if (days < 1 || days > 366) {
      throw ArgumentError('Select a range of 1 to 366 days.');
    }
  }

  final DateTime start;
  final DateTime end;
  DateTime get endExclusive => DateTime(end.year, end.month, end.day + 1);
  int get days =>
      DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays +
      1;
  ProgressRange get previous => ProgressRange(
        start: DateTime(start.year, start.month, start.day - days),
        end: DateTime(start.year, start.month, start.day - 1),
      );
  bool contains(DateTime date) =>
      !date.isBefore(start) && date.isBefore(endExclusive);
  String get label => '${calendarDate(start)} to ${calendarDate(end)}';

  @override
  bool operator ==(Object other) =>
      other is ProgressRange && start == other.start && end == other.end;
  @override
  int get hashCode => Object.hash(start, end);
}

class RecordedClimbs {
  const RecordedClimbs(this.system, this.grade, this.count);
  final ClimbingGradingSystem system;
  final String grade;
  final int count;
}

class RoutePerformance {
  const RoutePerformance({
    required this.system,
    required this.grade,
    required this.sent,
    required this.attempts,
    required this.name,
  });
  final ClimbingGradingSystem system;
  final String grade;
  final bool? sent;
  final int? attempts;
  final String name;
}

class CircuitPerformance {
  const CircuitPerformance({
    required this.key,
    required this.name,
    required this.prescription,
    required this.completedRows,
    required this.totalRows,
  });
  final String key;
  final String name;
  final List<ClimbingCircuitRow> prescription;
  final int completedRows;
  final int totalRows;
}

class ClimbingSession {
  const ClimbingSession({
    required this.instanceId,
    required this.athleteId,
    required this.templateId,
    required this.version,
    required this.date,
    required this.climbs,
    required this.routes,
    required this.circuits,
    required this.unrecordedBlocks,
    required this.legacyRoutes,
    this.workoutName = 'Workout',
    this.programId,
    this.programName,
  });
  final String instanceId;
  final String athleteId;
  final String workoutName;
  final String? programId;
  final String? programName;
  (String, String) get selectionKey => (athleteId, instanceId);
  final String templateId;
  final int version;
  final DateTime date;
  final List<RecordedClimbs> climbs;
  final List<RoutePerformance> routes;
  final List<CircuitPerformance> circuits;
  final int unrecordedBlocks;
  final int legacyRoutes;
  String get sourceLabel =>
      '$workoutName ${calendarDate(date)} - version $version';
  int? get recordedClimbs => climbs.isEmpty
      ? null
      : climbs.fold<int>(0, (sum, entry) => sum + entry.count);

  static ClimbingSession? fromWorkout(
    WorkoutInstance instance,
    WorkoutTemplateVersion version, {
    String workoutName = 'Workout',
    String? programName,
  }) {
    if (!instance.isCompleted) return null;
    if (instance.workoutTemplateVersion != version.versionNumber) {
      throw StateError(
        'Progress requires the workout instance\'s pinned version',
      );
    }
    final blocks = version.blocks
        .where(
          (block) =>
              block is ClimbingRouteBlock ||
              block is ClimbingCircuitBlock ||
              block is FreeClimbingBlock,
        )
        .toList();
    if (blocks.isEmpty) return null;
    if (instance.completedAt == null) {
      throw StateError(
        'Completed workout ${instance.id} has no completion time',
      );
    }
    final climbs = <RecordedClimbs>[];
    final routes = <RoutePerformance>[];
    final circuits = <CircuitPerformance>[];
    var unrecorded = 0;
    var legacy = 0;
    for (final block in blocks) {
      final slot = block.slots.single;
      var actual = instance.actualsBySlot[slot.slotId];
      // Legacy exercise-ID results can only be joined to an unambiguous slot.
      if (actual == null &&
          version.exerciseSlots
                  .where((s) => s.exerciseId == slot.exerciseId)
                  .length ==
              1) {
        final candidates = instance.actuals
            .where(
              (a) => !a.hasExplicitSlotId && a.exerciseId == slot.exerciseId,
            )
            .toList();
        if (candidates.length == 1) actual = candidates.single;
      }
      if (block is ClimbingRouteBlock && block.gradingSystem == null) {
        legacy++;
        continue;
      }
      if (actual == null) {
        unrecorded++;
        continue;
      }
      if (actual.exerciseId != slot.exerciseId) {
        throw StateError(
          'Result ${slot.slotId} does not match its pinned exercise',
        );
      }
      actual.validateForBlock(block);
      if (block is ClimbingRouteBlock) {
        final system = block.gradingSystem!;
        validateClimbingGrade(system, block.grade);
        routes.add(
          RoutePerformance(
            system: system,
            grade: block.grade,
            sent: actual.sent,
            attempts: actual.attempts,
            name: block.title ?? slot.exerciseName ?? 'Single route',
          ),
        );
        if (actual.sent == null) {
          unrecorded++;
        } else {
          climbs.add(RecordedClimbs(system, block.grade, actual.sent! ? 1 : 0));
        }
      } else if (block is ClimbingCircuitBlock) {
        var completed = 0;
        for (var i = 0; i < block.rows.length; i++) {
          final row = block.rows[i];
          if (actual.circuitRows![i].completed) {
            completed++;
            climbs
                .add(RecordedClimbs(row.gradingSystem, row.grade, row.climbs));
          } else {
            // An unchecked row does not tell us its partial climb count.
            unrecorded++;
          }
        }
        circuits.add(
          CircuitPerformance(
            key:
                '${instance.workoutTemplateId}/${version.versionNumber}/${block.blockId}',
            name: block.title ?? 'Climbing Circuit',
            prescription: block.rows,
            completedRows: completed,
            totalRows: block.rows.length,
          ),
        );
      } else if (block is FreeClimbingBlock) {
        if (actual.freeRows!.isEmpty) unrecorded++;
        for (final row in actual.freeRows!) {
          climbs.add(RecordedClimbs(row.gradingSystem, row.grade, row.climbs));
        }
      }
    }
    return ClimbingSession(
      instanceId: instance.id,
      athleteId: instance.athleteId,
      workoutName: workoutName,
      programId: progressProgramId(instance),
      programName: programName,
      templateId: instance.workoutTemplateId,
      version: version.versionNumber,
      date: instance.completedAt!.toLocal(),
      climbs: List.unmodifiable(climbs),
      routes: List.unmodifiable(routes),
      circuits: List.unmodifiable(circuits),
      unrecordedBlocks: unrecorded,
      legacyRoutes: legacy,
    );
  }
}

// Ad-hoc workouts also have a programId for authorization, not membership.
String? progressProgramId(WorkoutInstance instance) =>
    instance.resolvedProgramInstanceId != null || instance.programVersion > 0
        ? instance.programId
        : null;

class ProgressWorkoutGroup {
  ProgressWorkoutGroup({
    required this.key,
    required this.title,
    required List<ClimbingSession> sessions,
  }) : sessions = List.unmodifiable(sessions);
  final String key;
  final String title;
  final List<ClimbingSession> sessions;

  bool? selectionValue(Set<(String, String)> excluded) {
    final included = sessions
        .where((session) => !excluded.contains(session.selectionKey))
        .length;
    if (included == 0) return false;
    if (included == sessions.length) return true;
    return null;
  }
}

class ClimbingSummary {
  ClimbingSummary(Iterable<ClimbingSession> source)
      : sessions = List.unmodifiable(source);
  final List<ClimbingSession> sessions;
  int get sessionCount => sessions.length;
  int get incompleteSessions => sessions
      .where((s) => s.unrecordedBlocks > 0 || s.legacyRoutes > 0)
      .length;
  int? get recordedClimbs {
    final values = sessions.map((s) => s.recordedClimbs).whereType<int>();
    return values.isEmpty ? null : values.fold<int>(0, (a, b) => a + b);
  }

  Map<String, int> gradeCounts(ClimbingGradingSystem system) {
    final counts = <String, int>{};
    for (final session in sessions) {
      for (final entry in session.climbs.where((c) => c.system == system)) {
        if (entry.count > 0) {
          counts.update(
            entry.grade,
            (n) => n + entry.count,
            ifAbsent: () => entry.count,
          );
        }
      }
    }
    return {
      for (final grade in system.grades)
        if (counts.containsKey(grade)) grade: counts[grade]!,
    };
  }

  String? highestSend(ClimbingGradingSystem system) {
    final grades = [
      for (final session in sessions)
        for (final route in session.routes)
          if (route.system == system && route.sent == true) route.grade,
    ];
    if (grades.isEmpty) return null;
    grades.sort(
      (a, b) => system.grades.indexOf(a).compareTo(system.grades.indexOf(b)),
    );
    return grades.last;
  }

  int? recordedFor(ClimbingGradingSystem system) {
    final entries = sessions
        .expand((session) => session.climbs)
        .where((entry) => entry.system == system);
    return entries.isEmpty
        ? null
        : entries.fold<int>(0, (sum, entry) => sum + entry.count);
  }
}

class ProgressBucket {
  ProgressBucket(this.range, this.summary);
  final ProgressRange range;
  final ClimbingSummary summary;
}

class ClimbingProgressReport {
  ClimbingProgressReport({
    required this.range,
    required List<ClimbingSession> sessions,
  })  : current =
            ClimbingSummary(sessions.where((s) => range.contains(s.date))),
        previous = ClimbingSummary(
          sessions.where((s) => range.previous.contains(s.date)),
        );
  final ProgressRange range;
  final ClimbingSummary current;
  final ClimbingSummary previous;

  List<ProgressWorkoutGroup> get workoutGroups {
    final groups = <String, List<ClimbingSession>>{};
    for (final session in [...current.sessions, ...previous.sessions]) {
      final key = session.programId == null
          ? 'independent'
          : 'program:${session.programId}';
      groups.putIfAbsent(key, () => []).add(session);
    }
    final result = [
      for (final entry in groups.entries)
        ProgressWorkoutGroup(
          key: entry.key,
          title: entry.key == 'independent'
              ? 'Independent workouts'
              : entry.value.first.programName ??
                  'Program details unavailable (${entry.value.first.programId})',
          sessions: entry.value..sort((a, b) => b.date.compareTo(a.date)),
        ),
    ];
    result.sort((a, b) {
      if (a.key == 'independent') return b.key == 'independent' ? 0 : 1;
      if (b.key == 'independent') return -1;
      final titleOrder = a.title.compareTo(b.title);
      return titleOrder == 0 ? a.key.compareTo(b.key) : titleOrder;
    });
    return result;
  }

  ClimbingProgressReport excluding(Set<(String, String)> excluded) =>
      ClimbingProgressReport(
        range: range,
        sessions: [...current.sessions, ...previous.sessions]
            .where((session) => !excluded.contains(session.selectionKey))
            .toList(),
      );

  List<ProgressBucket> get buckets {
    final result = <ProgressBucket>[];
    var start = range.start;
    while (!start.isAfter(range.end)) {
      final next = range.days <= 14
          ? DateTime(start.year, start.month, start.day + 1)
          : range.days <= 90
              ? DateTime(start.year, start.month, start.day + 7)
              : DateTime(start.year, start.month + 1);
      final last = DateTime(next.year, next.month, next.day - 1);
      final bucketRange = ProgressRange(
        start: start,
        end: last.isAfter(range.end) ? range.end : last,
      );
      result.add(
        ProgressBucket(
          bucketRange,
          ClimbingSummary(
            current.sessions.where((s) => bucketRange.contains(s.date)),
          ),
        ),
      );
      start = next;
    }
    return result;
  }

  List<ProgressBucket> get weeklyBuckets {
    final result = <ProgressBucket>[];
    var start = range.start;
    while (!start.isAfter(range.end)) {
      final next = DateTime(
        start.year,
        start.month,
        start.day + 8 - start.weekday,
      );
      final last = DateTime(next.year, next.month, next.day - 1);
      final bucketRange = ProgressRange(
        start: start,
        end: last.isAfter(range.end) ? range.end : last,
      );
      result.add(
        ProgressBucket(
          bucketRange,
          ClimbingSummary(
            current.sessions
                .where((session) => bucketRange.contains(session.date)),
          ),
        ),
      );
      start = next;
    }
    return result;
  }
}
