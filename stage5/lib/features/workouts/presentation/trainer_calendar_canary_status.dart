import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

class TrainerCalendarCanaryStatus extends ConsumerWidget {
  const TrainerCalendarCanaryStatus({
    required this.instance,
    required this.athleteName,
    required this.programName,
    super.key,
  });

  final WorkoutInstance instance;
  final String? athleteName;
  final String? programName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (athleteName == null || athleteName == instance.athleteId) {
      return const SizedBox.shrink();
    }
    if (programName == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        markBrowserSmokeSurfaceFailure('trainer-calendar', 'missing-program');
      });
      return const SizedBox.shrink();
    }
    final repository = ref.watch(workoutTemplateRepositoryProvider);
    return FutureBuilder(
      future: repository.getById(instance.workoutTemplateId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final workout = snapshot.data;
            if (snapshot.hasError) {
              markBrowserSmokeSurfaceFailure('trainer-calendar', 'error');
            } else if (workout == null) {
              markBrowserSmokeSurfaceFailure(
                'trainer-calendar',
                'missing-workout',
              );
            } else {
              markBrowserSmokeSurfaceReady(
                'trainer-calendar',
                content: '$athleteName | $programName | ${workout.name}',
              );
            }
          });
        }
        return const SizedBox.shrink();
      },
    );
  }
}
