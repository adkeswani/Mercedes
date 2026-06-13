import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage3/features/auth/presentation/auth_providers.dart';
import 'package:stage3/features/exercises/data/exercise_note_repository.dart';
import 'package:stage3/features/exercises/domain/exercise_note.dart';

/// Provides the [ExerciseNoteRepository] scoped to the current user.
///
/// Returns null if not signed in.
final exerciseNoteRepositoryProvider =
    Provider<ExerciseNoteRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return ExerciseNoteRepository(userId: user.uid);
});

/// Streams all exercise notes for the current user as a lookup map.
///
/// Key: exerciseTemplateId, Value: ExerciseNote.
/// Empty map when not signed in or no notes exist.
final exerciseNotesProvider =
    StreamProvider<Map<String, ExerciseNote>>((ref) {
  final repo = ref.watch(exerciseNoteRepositoryProvider);
  if (repo == null) return Stream.value({});
  return repo.watchNotes();
});
