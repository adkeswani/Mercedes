import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage3/core/enums.dart';
import 'package:stage3/features/auth/presentation/app_entry_providers.dart';
import 'package:stage3/features/workouts/domain/workout_instance.dart';
import 'package:stage3/features/workouts/presentation/workout_instance_providers.dart';

/// Screen showing an athlete's workout history within a specific program.
///
/// Accessible by tapping an athlete in the inline roster or roster screen.
/// Shows all workout instances (scheduled, completed, missed, cancelled)
/// for the program-athlete pair.
class AthleteScheduleScreen extends ConsumerWidget {
  const AthleteScheduleScreen({
    super.key,
    required this.programId,
    required this.athleteId,
  });

  final String programId;
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(
      programAthleteScheduleProvider(
        ProgramAthleteKey(programId: programId, athleteId: athleteId),
      ),
    );

    // Resolve athlete name
    final profileRepo = ref.watch(userProfileRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder(
          future: profileRepo.getUserProfile(athleteId),
          builder: (context, snapshot) {
            final name = snapshot.data?.displayName ?? 'Athlete';
            return Text("$name's Schedule");
          },
        ),
      ),
      body: scheduleAsync.when(
        data: (instances) {
          if (instances.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No workouts assigned yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: instances.length,
            itemBuilder: (context, index) {
              final instance = instances[index];
              return _InstanceTile(instance: instance);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _InstanceTile extends StatelessWidget {
  const _InstanceTile({required this.instance});

  final WorkoutInstance instance;

  Color _statusColor(BuildContext context) {
    switch (instance.status) {
      case WorkoutInstanceStatus.scheduled:
        return Theme.of(context).colorScheme.primary;
      case WorkoutInstanceStatus.completed:
        return Colors.green;
      case WorkoutInstanceStatus.missed:
        return Colors.orange;
      case WorkoutInstanceStatus.cancelled:
        return Colors.grey;
    }
  }

  IconData _statusIcon() {
    switch (instance.status) {
      case WorkoutInstanceStatus.scheduled:
        return Icons.schedule;
      case WorkoutInstanceStatus.completed:
        return Icons.check_circle;
      case WorkoutInstanceStatus.missed:
        return Icons.warning_amber;
      case WorkoutInstanceStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context);

    return ListTile(
      leading: Icon(_statusIcon(), color: color),
      title: Text(instance.scheduledDate),
      subtitle: Text(
        '${instance.workoutType.name} · ${instance.status.name}'
        '${instance.rpe != null ? ' · RPE ${instance.rpe}' : ''}'
        '${instance.durationMinutes != null ? ' · ${instance.durationMinutes}min' : ''}',
      ),
      trailing: instance.isScheduled
          ? const Icon(Icons.chevron_right)
          : null,
      onTap: instance.isScheduled
          ? () => context.push('/workouts/complete/${instance.id}')
          : null,
    );
  }
}
