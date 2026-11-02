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
    this.athleteView = false,
    super.key,
  });

  final WorkoutInstance instance;
  final String? athleteName;
  final String? programName;
  final bool athleteView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!athleteView &&
        (athleteName == null || athleteName == instance.athleteId)) {
      return const SizedBox.shrink();
    }
    if (!athleteView && programName == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        markBrowserSmokeSurfaceFailure('trainer-calendar', 'missing-program');
      });
      return const SizedBox.shrink();
    }
    final repository = ref.watch(workoutTemplateRepositoryProvider);
    final marker = athleteView ? 'athlete-calendar' : 'trainer-calendar';
    return FutureBuilder(
      future: repository.getById(instance.workoutTemplateId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final workout = snapshot.data;
            if (snapshot.hasError) {
              markBrowserSmokeSurfaceFailure(marker, 'error');
            } else if (workout == null) {
              markBrowserSmokeSurfaceFailure(
                marker,
                'missing-workout',
              );
            } else {
              markBrowserSmokeSurfaceReady(
                marker,
                content: athleteView
                    ? workout.name
                    : '$athleteName | $programName | ${workout.name}',
              );
            }
          });
        }
        return const SizedBox.shrink();
      },
    );
  }
}
