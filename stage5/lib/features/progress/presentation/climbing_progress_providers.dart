import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/progress/data/climbing_progress_repository.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

final progressClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

final climbingProgressRepositoryProvider = Provider<ClimbingProgressRepository>(
  (ref) => ClimbingProgressRepository(
    instances: ref.watch(workoutInstanceRepositoryProvider),
    templates: ref.watch(workoutTemplateRepositoryProvider),
  ),
);

final climbingProgressProvider = FutureProvider.autoDispose
    .family<ClimbingProgressReport, ProgressRange>((ref, range) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) throw StateError('Sign in to view your climbing progress.');
  return ref.watch(climbingProgressRepositoryProvider).load(
        athleteId: user.uid,
        range: range,
      );
});
