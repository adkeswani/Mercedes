import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_organizer.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_delete_command.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

/// Displays the user's workout template library.
class WorkoutListScreen extends ConsumerStatefulWidget {
  const WorkoutListScreen({super.key});

  @override
  ConsumerState<WorkoutListScreen> createState() => _WorkoutListScreenState();
}

class _WorkoutListScreenState extends ConsumerState<WorkoutListScreen> {
  final Set<String> _removedWorkoutIds = {};

  @override
  Widget build(BuildContext context) {
    final workoutsAsync = ref.watch(workoutTemplatesProvider);
    final foldersAsync = ref.watch(
      libraryFoldersProvider(LibraryItemType.workout),
    );
    final clientNames =
        ref.watch(activeTrainerClientNamesProvider).valueOrNull ?? const {};
    final userId = ref.watch(authStateProvider).valueOrNull?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Workout Templates')),
      body: workoutsAsync.when(
        data: (workouts) {
          final visibleWorkouts = workouts
              .where((workout) => !_removedWorkoutIds.contains(workout.id))
              .toList();
          if (workouts.isEmpty) {
            if (browserAutomationEnabled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                markBrowserSmokeSurfaceFailure('trainer-workouts', 'empty');
              });
            }
          }
          if (userId == null) {
            return const Center(child: Text('Sign in to view your library.'));
          }
          return foldersAsync.when(
            data: (folders) {
              final scopedClientIds = workouts
                  .map((workout) => workout.clientAthleteId)
                  .whereType<String>();
              if (browserAutomationEnabled &&
                  workouts.isNotEmpty &&
                  scopedClientIds.every(clientNames.containsKey)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  markBrowserSmokeSurfaceReady(
                    'trainer-workouts',
                    content: [
                      workouts.first.name,
                      ...workouts.first.tags,
                      ...folders.map((folder) => folder.name),
                      'Clients',
                      'Unfiled',
                    ].join(' | '),
                  );
                });
              }
              return LibraryOrganizer<WorkoutTemplate>(
                userId: userId,
                itemType: LibraryItemType.workout,
                items: visibleWorkouts,
                folders: folders,
                emptyMessage: 'No workout templates yet. Tap + to create one.',
                nameOf: (item) => item.name,
                tagsOf: (item) => item.tags,
                folderIdOf: (item) => item.folderId,
                clientAthleteIdOf: (item) => item.clientAthleteId,
                activeClientNames: clientNames,
                supportsClientScope: true,
                tileBuilder: (context, item, organizationButton) =>
                    _WorkoutTile(
                  workout: item,
                  organizationButton: organizationButton,
                  onDismissed: () {
                    setState(() => _removedWorkoutIds.add(item.id));
                    ref.invalidate(workoutTemplatesProvider);
                  },
                ),
                updateOrganization: (
                  item, {
                  required tags,
                  required folderId,
                  required clientAthleteId,
                }) =>
                    ref
                        .read(workoutTemplateRepositoryProvider)
                        .updateOrganization(
                          id: item.id,
                          tags: tags,
                          folderId: folderId,
                          clientAthleteId: clientAthleteId,
                          updateClientScope: true,
                          userId: userId,
                        ),
                createFolder: (name) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.workout),
                    )
                    .create(name: name, userId: userId),
                renameFolder: (folder, name) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.workout),
                    )
                    .rename(folderId: folder.id, name: name, userId: userId),
                deleteFolder: (folder) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.workout),
                    )
                    .delete(folderId: folder.id, userId: userId),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => LibraryLoadError(
              message: 'Could not load folders: $error',
              onRetry: () => ref.invalidate(
                libraryFoldersProvider(LibraryItemType.workout),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          if (browserAutomationEnabled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              markBrowserSmokeSurfaceFailure('trainer-workouts', 'error');
            });
          }
          return LibraryLoadError(
            message: 'Could not load workouts: $e',
            onRetry: () => ref.invalidate(workoutTemplatesProvider),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/workouts/new'),
        tooltip: 'New workout template',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _WorkoutTile extends ConsumerWidget {
  const _WorkoutTile({
    required this.workout,
    required this.organizationButton,
    required this.onDismissed,
  });

  final WorkoutTemplate workout;
  final Widget organizationButton;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionLabel =
        workout.hasPublishedVersion ? 'v${workout.currentVersion}' : 'Draft';
    final deletePending =
        ref.watch(workoutDeleteControllerProvider).contains(workout.id);

    return Dismissible(
      key: ValueKey<String>('workout-${workout.id}'),
      direction:
          deletePending ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        final result = await confirmAndDeleteWorkout(
          context: context,
          ref: ref,
          workoutId: workout.id,
          workoutName: workout.name,
        );
        return result.deleted;
      },
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        title: Text(workout.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                LibraryMetadataLabel(label: workout.workoutType.name),
                LibraryMetadataLabel(label: versionLabel),
                for (final tag in workout.tags) LibraryTagLabel(tag: tag),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            organizationButton,
            if (workout.hasPublishedVersion)
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Duplicate workout',
                onPressed: () => _duplicateWorkout(context, ref),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => context.push('/workouts/${workout.id}'),
      ),
    );
  }

  Future<void> _duplicateWorkout(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) {
      return;
    }

    final repo = ref.read(workoutTemplateRepositoryProvider);
    try {
      final newId = await repo.duplicateTemplate(
        sourceTemplateId: workout.id,
        userId: uid,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Workout duplicated')));
        context.push('/workouts/$newId?copyFrom=${workout.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to duplicate: $e')));
      }
    }
  }
}
