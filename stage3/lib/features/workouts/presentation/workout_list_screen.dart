import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage3/features/auth/presentation/auth_providers.dart';
import 'package:stage3/features/workouts/domain/workout_template.dart';
import 'package:stage3/features/workouts/presentation/workout_providers.dart';

/// Displays the user's workout template library.
class WorkoutListScreen extends ConsumerWidget {
  const WorkoutListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutsAsync = ref.watch(workoutTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Templates'),
      ),
      body: workoutsAsync.when(
        data: (workouts) {
          if (workouts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sports_gymnastics,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No workout templates yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first workout'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: workouts.length,
            itemBuilder: (context, index) {
              final workout = workouts[index];
              return _WorkoutTile(workout: workout);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
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
  const _WorkoutTile({required this.workout});

  final WorkoutTemplate workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionLabel = workout.hasPublishedVersion
        ? 'v${workout.currentVersion}'
        : 'Draft';

    return Dismissible(
      key: Key(workout.id),
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
        final repo = ref.read(workoutTemplateRepositoryProvider);
        final referenced = await repo.isWorkoutReferenced(workout.id);
        if (referenced) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Cannot delete — this workout is used in a program',
                ),
              ),
            );
          }
          return false;
        }
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete workout template?'),
            content: Text(
              'Are you sure you want to delete "${workout.name}"?',
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
        ref.read(workoutTemplateRepositoryProvider).softDelete(
          workout.id,
          uid,
        );
      },
      child: ListTile(
        title: Text(workout.name),
        subtitle: Text(
          '${workout.workoutType.name} · $versionLabel',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    if (uid == null) return;

    final repo = ref.read(workoutTemplateRepositoryProvider);
    try {
      final newId = await repo.duplicateTemplate(
        sourceTemplateId: workout.id,
        userId: uid,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workout duplicated')),
        );
        context.push('/workouts/$newId?copyFrom=${workout.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to duplicate: $e')),
        );
      }
    }
  }
}
