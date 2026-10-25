import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/relationships/domain/trainer_client_workspace.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';

/// Currently selected client (athleteId) in the trainer client workspace.
///
/// `null` means no client is selected yet (e.g. before the roster loads).
final selectedWorkspaceAthleteIdProvider = StateProvider<String?>((ref) {
  return null;
});

/// Streams the selected athlete's workout instances for the bounded
/// recent/upcoming window used by the Schedule and Workouts tabs.
///
/// Mirrors `athleteCalendarProvider`, scoped to the workspace's selected
/// client and a fixed recent/upcoming window instead of a caller-supplied
/// date range.
final clientWorkspaceScheduleProvider =
    StreamProvider.autoDispose<List<WorkoutInstance>>((ref) {
  final athleteId = ref.watch(selectedWorkspaceAthleteIdProvider);
  final owner = ref.watch(authStateProvider).value;
  if (athleteId == null || owner == null) return const Stream.empty();

  final today = DateTime.now();
  final startDate =
      addDays(_isoDate(today), -clientWorkspaceScheduleLookbackDays);
  final endDate =
      addDays(_isoDate(today), clientWorkspaceScheduleLookaheadDays);

  final repo = ref.watch(workoutInstanceRepositoryProvider);
  return repo.watchAthleteCalendar(
    ownerId: owner.uid,
    athleteId: athleteId,
    startDate: startDate,
    endDate: endDate,
  );
});

String _isoDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
