import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage2/features/auth/presentation/auth_providers.dart';
import 'package:stage2/features/programs/data/program_repository.dart';
import 'package:stage2/features/programs/domain/program.dart';

/// Singleton repository for programs.
final programRepositoryProvider = Provider<ProgramRepository>((ref) {
  return ProgramRepository();
});

/// Streams all non-deleted programs for the current user.
final programsProvider = StreamProvider<List<Program>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(programRepositoryProvider);
  return repo.watchAll(user.uid);
});

/// Local draft state for the program builder.
///
/// Holds the workout references being edited before publishing.
/// Reset when entering the builder, persisted only on publish.
class ProgramDraftNotifier extends StateNotifier<List<ProgramWorkoutRef>> {
  ProgramDraftNotifier() : super([]);

  /// Replaces the entire draft (e.g. when loading from existing version).
  void load(List<ProgramWorkoutRef> workouts) {
    state = List.of(workouts);
  }

  /// Adds a workout reference to the draft.
  void addWorkout(ProgramWorkoutRef ref) {
    state = [...state, ref];
  }

  /// Removes the workout at [index].
  void removeAt(int index) {
    final updated = List.of(state);
    updated.removeAt(index);
    // Reassign sort orders to keep them contiguous
    state = [
      for (var i = 0; i < updated.length; i++)
        ProgramWorkoutRef(
          workoutTemplateId: updated[i].workoutTemplateId,
          workoutTemplateVersion: updated[i].workoutTemplateVersion,
          sortOrder: i,
        ),
    ];
  }

  /// Reorders a workout from [oldIndex] to [newIndex].
  void reorder(int oldIndex, int newIndex) {
    final updated = List.of(state);
    if (newIndex > oldIndex) newIndex--;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    // Reassign sort orders
    state = [
      for (var i = 0; i < updated.length; i++)
        ProgramWorkoutRef(
          workoutTemplateId: updated[i].workoutTemplateId,
          workoutTemplateVersion: updated[i].workoutTemplateVersion,
          sortOrder: i,
        ),
    ];
  }

  /// Clears the draft.
  void clear() {
    state = [];
  }
}

/// Provider for the program builder draft state.
final programDraftProvider =
    StateNotifierProvider<ProgramDraftNotifier, List<ProgramWorkoutRef>>((ref) {
  return ProgramDraftNotifier();
});
