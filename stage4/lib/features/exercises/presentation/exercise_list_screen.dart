import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/exercises/domain/exercise_template.dart';
import 'package:stage4/features/exercises/presentation/exercise_providers.dart';

/// Displays the user's exercise template library.
///
/// Shows a list of templates with a FAB to create new ones.
/// Tap to edit, swipe to soft-delete.
class ExerciseListScreen extends ConsumerWidget {
  const ExerciseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(exerciseTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Library'),
      ),
      body: exercisesAsync.when(
        data: (exercises) {
          if (exercises.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fitness_center,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No exercises yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first exercise'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: exercises.length,
            itemBuilder: (context, index) {
              final exercise = exercises[index];
              return _ExerciseTile(exercise: exercise);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
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
  const _ExerciseTile({required this.exercise});

  final ExerciseTemplate exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(exercise.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: Icon(
          Icons.delete,
          color: Theme.of(context).colorScheme.onError,
        ),
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
        ref.read(exerciseTemplateRepositoryProvider).softDelete(
          exercise.id,
          uid,
        );
      },
      child: ListTile(
        title: Text(exercise.name),
        subtitle: Text(
          exercise.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/exercises/${exercise.id}'),
      ),
    );
  }
}
