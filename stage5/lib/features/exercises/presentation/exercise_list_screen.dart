import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_organizer.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';

/// Displays the user's exercise template library.
///
/// Shows a list of templates with a FAB to create new ones.
/// Tap to edit, swipe to soft-delete.
class ExerciseListScreen extends ConsumerWidget {
  const ExerciseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(exerciseTemplatesProvider);
    final foldersAsync = ref.watch(
      libraryFoldersProvider(LibraryItemType.exercise),
    );
    final userId = ref.watch(authStateProvider).valueOrNull?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Exercise Library')),
      body: exercisesAsync.when(
        data: (exercises) {
          if (exercises.isEmpty) {
            if (browserAutomationEnabled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                markBrowserSmokeSurfaceFailure('trainer-exercises', 'empty');
              });
            }
          }
          if (userId == null) {
            return const Center(child: Text('Sign in to view your library.'));
          }
          return foldersAsync.when(
            data: (folders) {
              if (browserAutomationEnabled && exercises.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  markBrowserSmokeSurfaceReady(
                    'trainer-exercises',
                    content: [
                      exercises.first.name,
                      ...exercises.first.tags,
                      ...folders.map((folder) => folder.name),
                      'Unfiled',
                    ].join(' | '),
                  );
                });
              }
              return LibraryOrganizer<ExerciseTemplate>(
                userId: userId,
                itemType: LibraryItemType.exercise,
                items: exercises,
                folders: folders,
                emptyMessage: 'No exercises yet. Tap + to create one.',
                nameOf: (item) => item.name,
                tagsOf: (item) => item.tags,
                folderIdOf: (item) => item.folderId,
                clientAthleteIdOf: (_) => null,
                tileBuilder: (context, item, organizationButton) =>
                    _ExerciseTile(
                  exercise: item,
                  organizationButton: organizationButton,
                ),
                updateOrganization: (
                  item, {
                  required tags,
                  required folderId,
                  required clientAthleteId,
                }) =>
                    ref
                        .read(exerciseTemplateRepositoryProvider)
                        .updateOrganization(
                          id: item.id,
                          tags: tags,
                          folderId: folderId,
                          userId: userId,
                        ),
                createFolder: (name) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.exercise),
                    )
                    .create(name: name, userId: userId),
                renameFolder: (folder, name) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.exercise),
                    )
                    .rename(folderId: folder.id, name: name, userId: userId),
                deleteFolder: (folder) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.exercise),
                    )
                    .delete(folderId: folder.id, userId: userId),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => LibraryLoadError(
              message: 'Could not load folders: $error',
              onRetry: () => ref.invalidate(
                libraryFoldersProvider(LibraryItemType.exercise),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          if (browserAutomationEnabled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              markBrowserSmokeSurfaceFailure('trainer-exercises', 'error');
            });
          }
          return LibraryLoadError(
            message: 'Could not load exercises: $e',
            onRetry: () => ref.invalidate(exerciseTemplatesProvider),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/exercises/new'),
        tooltip: 'New exercise',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ExerciseTile extends ConsumerWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.organizationButton,
  });

  final ExerciseTemplate exercise;
  final Widget organizationButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(exercise.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      confirmDismiss: (direction) async {
        final repo = ref.read(exerciseTemplateRepositoryProvider);
        final referenced = await repo.isExerciseReferenced(exercise.id);
        if (referenced) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Cannot delete — this exercise is used in a workout',
                ),
              ),
            );
          }
          return false;
        }
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete exercise?'),
            content: Text(
              'Are you sure you want to delete "${exercise.name}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        final uid = ref.read(authStateProvider).value?.uid;
        if (uid == null) return;
        ref
            .read(exerciseTemplateRepositoryProvider)
            .softDelete(exercise.id, uid);
      },
      child: ListTile(
        title: Text(exercise.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exercise.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (exercise.tags.isNotEmpty)
              Wrap(
                spacing: 4,
                children: [
                  for (final tag in exercise.tags)
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [organizationButton, const Icon(Icons.chevron_right)],
        ),
        onTap: () => context.push('/exercises/${exercise.id}'),
      ),
    );
  }
}
