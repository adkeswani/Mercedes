import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/auth/presentation/home_screen.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

class AthleteWorkoutHistoryScreen extends ConsumerWidget {
  const AthleteWorkoutHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(athleteWorkoutHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workout history')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (browserAutomationEnabled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              markBrowserSmokeSurfaceFailure('athlete-history', 'error');
            });
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load workout history: $error',
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
        data: (instances) {
          if (instances.isEmpty) {
            if (browserAutomationEnabled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                markBrowserSmokeSurfaceFailure('athlete-history', 'empty');
              });
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No workout history yet. Completed and past workouts will '
                  'appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: instances.length,
            itemBuilder: (context, index) =>
                _WorkoutHistoryCard(instance: instances[index]),
          );
        },
      ),
    );
  }
}

class _WorkoutHistoryCard extends ConsumerWidget {
  const _WorkoutHistoryCard({required this.instance});

  final WorkoutInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref
        .watch(workoutTemplateRepositoryProvider)
        .getById(instance.workoutTemplateId);
    final status = workoutStatusLabel(instance.status);
    return FutureBuilder(
      future: template,
      builder: (context, snapshot) {
        if (browserAutomationEnabled &&
            snapshot.connectionState == ConnectionState.done) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (snapshot.hasData) {
              markBrowserSmokeSurfaceReady(
                'athlete-history',
                content: snapshot.data!.name,
              );
            } else {
              markBrowserSmokeSurfaceFailure(
                'athlete-history',
                'missing-workout',
              );
            }
          });
        }
        final title = snapshot.connectionState != ConnectionState.done
            ? 'Loading workout...'
            : snapshot.data?.name ?? 'Workout details unavailable';
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            button: instance.isCompleted,
            label: '$title, $status, ${instance.scheduledDate}',
            child: ListTile(
              leading: Icon(
                instance.isCompleted
                    ? Icons.check_circle
                    : Icons.history_outlined,
                color: instance.isCompleted ? Colors.green : null,
              ),
              title: Text(title),
              subtitle: Text(
                '${instance.scheduledDate} · $status'
                '${instance.rpe == null ? '' : ' · RPE ${instance.rpe}'}'
                '${instance.durationMinutes == null ? '' : ' · '
                    '${instance.durationMinutes} min'}',
              ),
              trailing:
                  instance.isCompleted ? const Icon(Icons.chevron_right) : null,
              onTap: instance.isCompleted
                  ? () => context.push('/workouts/complete/${instance.id}')
                  : null,
            ),
          ),
        );
      },
    );
  }
}
