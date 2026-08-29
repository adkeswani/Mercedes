import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/data/exercise_template_repository.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';

/// Singleton repository for exercise templates.
final exerciseTemplateRepositoryProvider =
    Provider<ExerciseTemplateRepository>((ref) {
  return ExerciseTemplateRepository();
});

/// Idempotently materializes legacy exercises after their owner signs in.
final exerciseVersionBackfillForUserProvider =
    FutureProvider.family<int, String>((ref, userId) {
  final repo = ref.watch(exerciseTemplateRepositoryProvider);
  return repo.backfillOwnedLegacyExercises(userId);
});

/// Runs the owner-scoped backfill for the authenticated user.
final exerciseVersionBackfillProvider = FutureProvider<int>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return 0;
  return ref.watch(exerciseVersionBackfillForUserProvider(user.uid).future);
});

/// Streams all non-deleted exercise templates for the current user.
final exerciseTemplatesProvider =
    StreamProvider<List<ExerciseTemplate>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(exerciseTemplateRepositoryProvider);
  return repo.watchAll(user.uid);
});
