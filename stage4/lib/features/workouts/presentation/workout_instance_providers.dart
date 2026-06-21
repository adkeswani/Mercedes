import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/workouts/data/workout_instance_repository.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';

/// Singleton repository for workout instances.
final workoutInstanceRepositoryProvider =
    Provider<WorkoutInstanceRepository>((ref) {
  return WorkoutInstanceRepository();
});

/// Streams workout instances for the current user within a date range.
///
/// Use with `ref.watch(athleteScheduleProvider(DateRange(start, end)))`.
final athleteScheduleProvider =
    StreamProvider.family<List<WorkoutInstance>, DateRange>((ref, range) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(workoutInstanceRepositoryProvider);
  return repo.watchSchedule(
    athleteId: user.uid,
    startDate: range.startDate,
    endDate: range.endDate,
  );
});

/// Streams workout instances for a specific program-athlete pair.
///
/// Used by program owners to view an athlete's schedule.
final programAthleteScheduleProvider = StreamProvider.family<
    List<WorkoutInstance>, ProgramAthleteKey>((ref, key) {
  final repo = ref.watch(workoutInstanceRepositoryProvider);
  return repo.watchProgramSchedule(
    programId: key.programId,
    athleteId: key.athleteId,
  );
});

/// Key for date range queries.
class DateRange {
  const DateRange({required this.startDate, required this.endDate});
  final String startDate;
  final String endDate;

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      startDate == other.startDate &&
      endDate == other.endDate;

  @override
  int get hashCode => Object.hash(startDate, endDate);
}

/// Key for program + athlete pair queries.
class ProgramAthleteKey {
  const ProgramAthleteKey({
    required this.programId,
    required this.athleteId,
  });
  final String programId;
  final String athleteId;

  @override
  bool operator ==(Object other) =>
      other is ProgramAthleteKey &&
      programId == other.programId &&
      athleteId == other.athleteId;

  @override
  int get hashCode => Object.hash(programId, athleteId);
}
