import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage2/features/exercises/domain/exercise_template.dart';
import 'package:stage2/features/exercises/presentation/exercise_providers.dart';

/// Result returned from the exercise picker.
class ExercisePickerResult {
  const ExercisePickerResult({required this.id, required this.name});
  final String id;
  final String name;
}

/// Shows a modal bottom sheet to pick an exercise template.
///
/// Returns the selected exercise's ID and name, or null if cancelled.
Future<ExercisePickerResult?> showExercisePicker(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<ExercisePickerResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ExercisePickerSheet(),
  );
}

class _ExercisePickerSheet extends ConsumerWidget {
  const _ExercisePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(exerciseTemplatesProvider);

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
                    'Select Exercise',
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
              child: exercisesAsync.when(
                data: (exercises) {
                  if (exercises.isEmpty) {
                    return const Center(
                      child: Text('No exercises yet. Create one first.'),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = exercises[index];
                      return ListTile(
                        title: Text(exercise.name),
                        subtitle: Text(
                          exercise.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(
                          ExercisePickerResult(
                            id: exercise.id,
                            name: exercise.name,
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
