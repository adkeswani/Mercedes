import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage2/features/workouts/presentation/workout_providers.dart';

/// Result returned from the workout picker.
class WorkoutPickerResult {
  const WorkoutPickerResult({
    required this.id,
    required this.name,
    required this.currentVersion,
  });
  final String id;
  final String name;
  final int currentVersion;
}

/// Shows a modal bottom sheet to pick a published workout template.
///
/// Returns the selected workout's ID, name, and current version,
/// or null if cancelled. Only shows workouts with at least one
/// published version.
Future<WorkoutPickerResult?> showWorkoutPicker(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<WorkoutPickerResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _WorkoutPickerSheet(),
  );
}

class _WorkoutPickerSheet extends ConsumerWidget {
  const _WorkoutPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutsAsync = ref.watch(workoutTemplatesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Workout',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: workoutsAsync.when(
                data: (workouts) {
                  final published = workouts
                      .where((w) => w.hasPublishedVersion)
                      .toList();
                  if (published.isEmpty) {
                    return const Center(
                      child: Text(
                        'No published workouts yet.\n'
                        'Publish a workout template first.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: published.length,
                    itemBuilder: (context, index) {
                      final workout = published[index];
                      return ListTile(
                        title: Text(workout.name),
                        subtitle: Text(
                          '${workout.workoutType.name} · v${workout.currentVersion}',
                        ),
                        onTap: () => Navigator.of(context).pop(
                          WorkoutPickerResult(
                            id: workout.id,
                            name: workout.name,
                            currentVersion: workout.currentVersion,
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        );
      },
    );
  }
}
