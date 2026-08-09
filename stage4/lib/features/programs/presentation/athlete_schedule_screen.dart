import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';
import 'package:stage4/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage4/features/workouts/presentation/workout_providers.dart';

/// Shows an athlete's upcoming and past workout instances for one program.
class AthleteScheduleScreen extends ConsumerWidget {
  const AthleteScheduleScreen({
    super.key,
    required this.programId,
    required this.athleteId,
  });

  final String programId;
  final String athleteId;

  bool _isUpcoming(WorkoutInstance instance) {
    if (!instance.isScheduled) return false;
    final scheduled = DateTime.tryParse(instance.scheduledDate);
    if (scheduled == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !scheduled.isBefore(today);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(
      programAthleteScheduleProvider(
        ProgramAthleteKey(programId: programId, athleteId: athleteId),
      ),
    );
    final programRepo = ref.watch(programRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder(
          future: programRepo.getById(programId),
          builder: (context, snapshot) =>
              Text(snapshot.data?.name ?? 'Program Workouts'),
        ),
      ),
      body: scheduleAsync.when(
        data: (instances) {
          if (instances.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child:
                    Text('No workouts from this program are on your schedule.'),
              ),
            );
          }

          final upcoming = instances.where(_isUpcoming).toList()
            ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
          final past = instances.where((i) => !_isUpcoming(i)).toList()
            ..sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (upcoming.isNotEmpty) ...[
                const _SectionHeader('Upcoming'),
                ...upcoming.map((i) => _InstanceTile(instance: i)),
              ],
              if (past.isNotEmpty) ...[
                const _SectionHeader('Past'),
                ...past.map((i) => _InstanceTile(instance: i)),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _InstanceTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final canOpen = instance.isScheduled || instance.isCompleted;
    final workoutRepo = ref.watch(workoutTemplateRepositoryProvider);

    return ListTile(
      leading: Icon(_statusIcon(), color: _statusColor(context)),
      title: FutureBuilder(
        future: workoutRepo.getById(instance.workoutTemplateId),
        builder: (context, snapshot) => Text(snapshot.data?.name ?? 'Workout'),
      ),
      subtitle: Text(
        '${instance.scheduledDate} · ${instance.workoutType.name} · '
        '${instance.status.name}'
        '${instance.rpe != null ? ' · RPE ${instance.rpe}' : ''}'
        '${instance.durationMinutes != null ? ' · ${instance.durationMinutes}min' : ''}',
      ),
      trailing: canOpen ? const Icon(Icons.chevron_right) : null,
      onTap: canOpen
          ? () => context.push('/workouts/complete/${instance.id}')
          : null,
    );
  }
}
