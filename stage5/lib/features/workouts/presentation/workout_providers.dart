import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

/// Singleton repository for workout templates.
final workoutTemplateRepositoryProvider =
    Provider<WorkoutTemplateRepository>((ref) {
  return WorkoutTemplateRepository();
});

/// Streams all non-deleted workout templates for the current user.
final workoutTemplatesProvider = StreamProvider<List<WorkoutTemplate>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(workoutTemplateRepositoryProvider);
  return repo.watchAll(user.uid);
});

/// A workout exposed through the latest published version of a program.
class ProgramWorkoutOption {
  const ProgramWorkoutOption({
    required this.template,
    required this.version,
  });

  final WorkoutTemplate template;
  final int version;
}

/// Loads the distinct workouts available through a program's latest version.
///
/// Unlike [workoutTemplatesProvider], this is not creator-scoped: enrolled
/// athletes can read referenced shared templates and schedule them for
/// themselves.
final programWorkoutOptionsProvider =
    FutureProvider.family<List<ProgramWorkoutOption>, String>(
  (ref, programId) async {
    final programRepo = ref.watch(programRepositoryProvider);
    final workoutRepo = ref.watch(workoutTemplateRepositoryProvider);
    final entries = await programRepo.getLatestEntries(programId);
    final seen = <String>{};
    final options = <ProgramWorkoutOption>[];

    for (final entry in entries) {
      if (!seen.add(entry.workoutTemplateId)) continue;
      final template = await workoutRepo.getById(entry.workoutTemplateId);
      if (template == null) continue;
      options.add(
        ProgramWorkoutOption(
          template: template,
          version: entry.workoutTemplateVersion,
        ),
      );
    }
    options.sort(
      (a, b) => a.template.name.toLowerCase().compareTo(
            b.template.name.toLowerCase(),
          ),
    );
    return options;
  },
);

/// Local draft state for the workout builder.
///
/// Holds the exercise prescriptions being edited before publishing.
/// Reset when entering the builder, persisted only on publish.
class WorkoutDraftNotifier extends StateNotifier<List<ExercisePrescription>> {
  WorkoutDraftNotifier() : super([]);

  /// Replaces the entire draft (e.g. when loading from existing version).
  void load(List<ExercisePrescription> exercises) {
    state = List.of(exercises);
  }

  /// Adds an exercise to the draft.
  void addExercise(ExercisePrescription prescription) {
    state = [...state, prescription];
  }

  /// Removes the exercise at [index].
  void removeAt(int index) {
    final updated = List.of(state);
    updated.removeAt(index);
    // Reassign sort orders to keep them contiguous
    state = [
      for (var i = 0; i < updated.length; i++)
        updated[i].copyWith(sortOrder: i),
    ];
  }

  /// Updates the exercise at [index].
  void updateAt(int index, ExercisePrescription prescription) {
    final updated = List.of(state);
    updated[index] = prescription;
    state = updated;
  }

  /// Reorders an exercise from [oldIndex] to [newIndex].
  void reorder(int oldIndex, int newIndex) {
    final updated = List.of(state);
    if (newIndex > oldIndex) newIndex--;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    // Reassign sort orders
    state = [
      for (var i = 0; i < updated.length; i++)
        updated[i].copyWith(sortOrder: i),
    ];
  }

  /// Clears the draft.
  void clear() {
    state = [];
  }
}

/// Provider for the workout builder draft state.
final workoutDraftProvider =
    StateNotifierProvider<WorkoutDraftNotifier, List<ExercisePrescription>>(
        (ref) {
  return WorkoutDraftNotifier();
});
