import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage3/features/auth/presentation/auth_providers.dart';
import 'package:stage3/features/exercises/data/exercise_template_repository.dart';
import 'package:stage3/features/exercises/domain/exercise_template.dart';

/// Singleton repository for exercise templates.
final exerciseTemplateRepositoryProvider =
    Provider<ExerciseTemplateRepository>((ref) {
  return ExerciseTemplateRepository();
});

/// Streams all non-deleted exercise templates for the current user.
final exerciseTemplatesProvider =
    StreamProvider<List<ExerciseTemplate>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(exerciseTemplateRepositoryProvider);
  return repo.watchAll(user.uid);
});
