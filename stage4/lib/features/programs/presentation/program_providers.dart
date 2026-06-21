import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/programs/data/program_folder_repository.dart';
import 'package:stage4/features/programs/data/program_repository.dart';
import 'package:stage4/features/programs/domain/program.dart';

/// Singleton repository for programs.
final programRepositoryProvider = Provider<ProgramRepository>((ref) {
  return ProgramRepository();
});

/// Singleton repository for program folders.
final programFolderRepositoryProvider =
    Provider<ProgramFolderRepository>((ref) {
  return ProgramFolderRepository();
});

/// Streams all non-deleted programs for the current user.
final programsProvider = StreamProvider<List<Program>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(programRepositoryProvider);
  return repo.watchAll(user.uid);
});

/// Streams the current user's program folders.
final programFoldersProvider = StreamProvider<List<ProgramFolder>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(programFolderRepositoryProvider);
  return repo.watchFolders(user.uid);
});

/// Local draft state for the program builder.
///
/// Holds the schedule entries being edited before publishing.
/// Reset when entering the builder, persisted only on publish.
class ProgramDraftNotifier extends StateNotifier<List<ProgramScheduleEntry>> {
  ProgramDraftNotifier() : super([]);

  /// Replaces the entire draft (e.g. when loading from existing version).
  void load(List<ProgramScheduleEntry> entries) {
    state = List.of(entries);
  }

  /// Adds a schedule entry to the draft.
  void addWorkout(ProgramScheduleEntry entry) {
    state = [...state, entry];
  }

  /// Removes the entry at [index].
  void removeAt(int index) {
    final updated = List.of(state);
    updated.removeAt(index);
    // Reassign sort orders to keep them contiguous; preserve dayOffset.
    state = [
      for (var i = 0; i < updated.length; i++)
        updated[i].copyWith(sortOrder: i),
    ];
  }

  /// Reorders an entry from [oldIndex] to [newIndex].
  void reorder(int oldIndex, int newIndex) {
    final updated = List.of(state);
    if (newIndex > oldIndex) newIndex--;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    // Reassign sort orders; preserve dayOffset.
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

/// Provider for the program builder draft state.
final programDraftProvider =
    StateNotifierProvider<ProgramDraftNotifier, List<ProgramScheduleEntry>>(
        (ref) {
  return ProgramDraftNotifier();
});
