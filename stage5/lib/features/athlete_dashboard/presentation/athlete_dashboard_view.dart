import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/athlete_dashboard/domain/athlete_activity_event.dart';
import 'package:stage5/features/athlete_dashboard/presentation/athlete_dashboard_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart'
    show coachingReactions;
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_instance_labels.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

/// The athlete's Dashboard: filter chips (All, Today's Workouts, Completed,
/// Comments, Reactions) over Today's scheduled workouts and a completion/
/// comment/reaction activity feed, mirroring the trainer dashboard's
/// structure. Defaults to the All tab.
///
/// Rendered as a plain, non-scrolling [Column] so it can be embedded inside
/// the shared [HomeScreenContent]'s outer scroll view.
class AthleteDashboardView extends StatefulWidget {
  const AthleteDashboardView({super.key});

  @override
  State<AthleteDashboardView> createState() => _AthleteDashboardViewState();
}

class _AthleteDashboardViewState extends State<AthleteDashboardView> {
  AthleteActivityFilter _filter = AthleteActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: 'Dashboard filters',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in AthleteActivityFilter.values)
                _FilterControl(
                  filter: filter,
                  selected: _filter == filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_filter == AthleteActivityFilter.todaysWorkouts)
          const _TodaysWorkoutsSection()
        else
          _AthleteActivityFeed(filter: _filter),
      ],
    );
  }
}

class _FilterControl extends StatelessWidget {
  const _FilterControl({
    required this.filter,
    required this.selected,
    required this.onSelected,
  });

  final AthleteActivityFilter filter;
  final bool selected;
  final ValueChanged<AthleteActivityFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      AthleteActivityFilter.all => 'All',
      AthleteActivityFilter.todaysWorkouts => "Today's Workouts",
      AthleteActivityFilter.completed => 'Completed',
      AthleteActivityFilter.comments => 'Comments',
      AthleteActivityFilter.reactions => 'Reactions',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label filter',
      child: FilterChip(
        key: Key('athlete-dashboard-filter-${filter.name}'),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(filter),
      ),
    );
  }
}

class _AthleteActivityFeed extends ConsumerWidget {
  const _AthleteActivityFeed({required this.filter});

  final AthleteActivityFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(athleteDashboardProvider);
    return dashboard.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _FeedError(
        error: error,
        onRetry: () => ref.invalidate(athleteDashboardProvider),
      ),
      data: (page) {
        final events = filterAthleteActivityEvents(page.events, filter);
        if (events.isEmpty) {
          return _FeedEmpty(filter: filter);
        }
        return Column(
          children: [
            for (final event in events) ...[
              _ActivityCard(event: event),
              const SizedBox(height: 8),
            ],
            if (page.isBounded)
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Text('Showing the newest activity'),
              ),
          ],
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.event});

  final AthleteActivityEvent event;

  @override
  Widget build(BuildContext context) {
    if (event is AthleteCompletionActivityEvent) {
      final completion = event as AthleteCompletionActivityEvent;
      return _SimpleActivityCard(
        icon: Icons.check_circle_outline,
        title: 'You completed ${completion.workoutName}',
        detail: 'RPE ${completion.rpe} • ${completion.durationMinutes} min',
        occurredAt: completion.occurredAt,
      );
    }
    if (event is AthleteCommentActivityEvent) {
      final comment = event as AthleteCommentActivityEvent;
      return _SimpleActivityCard(
        icon: Icons.comment_outlined,
        title: '${comment.authorName} commented',
        detail: comment.comment,
        occurredAt: comment.occurredAt,
      );
    }
    final reaction = event as AthleteReactionActivityEvent;
    final definition = coachingReactions.firstWhere(
      (item) => item.id == reaction.reactionId,
    );
    return _SimpleActivityCard(
      icon: Icons.add_reaction_outlined,
      title: '${reaction.actorName} reacted',
      detail: '${definition.symbol} ${definition.label}',
      occurredAt: reaction.occurredAt,
    );
  }
}

class _SimpleActivityCard extends StatelessWidget {
  const _SimpleActivityCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.occurredAt,
  });

  final IconData icon;
  final String title;
  final String detail;
  final DateTime occurredAt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('$detail\n${_formatDateTime(occurredAt)}'),
        isThreeLine: true,
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unable to load activity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('$error'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty({required this.filter});

  final AthleteActivityFilter filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      AthleteActivityFilter.all => 'No recent activity',
      AthleteActivityFilter.todaysWorkouts => 'No workouts scheduled today',
      AthleteActivityFilter.completed => 'No completed workouts',
      AthleteActivityFilter.comments => 'No recent comments',
      AthleteActivityFilter.reactions => 'No recent reactions',
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.inbox_outlined),
        title: Text(message),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hour =
      local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} at '
      '$hour:${local.minute.toString().padLeft(2, '0')} $period';
}

/// Shows the current user's workouts scheduled for today, with quick access
/// to open details / mark completion.
class _TodaysWorkoutsSection extends ConsumerWidget {
  const _TodaysWorkoutsSection();

  String _formatIsoDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _formatIsoDate(DateTime.now());
    final scheduleAsync = ref.watch(
      athleteScheduleProvider(DateRange(startDate: today, endDate: today)),
    );

    return scheduleAsync.when(
      data: (instances) {
        if (instances.isEmpty) {
          return const _FeedEmpty(filter: AthleteActivityFilter.todaysWorkouts);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:
              instances.map((i) => _TodaysWorkoutTile(instance: i)).toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// A single today's-workout row that links to the completion/detail screen.
class _TodaysWorkoutTile extends ConsumerWidget {
  const _TodaysWorkoutTile({required this.instance});

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

  Future<List<String>> _loadNames(WidgetRef ref) {
    final workoutRepo = ref.watch(workoutTemplateRepositoryProvider);
    final programRepo = ref.watch(programRepositoryProvider);
    return Future.wait([
      workoutRepo
          .getById(instance.workoutTemplateId)
          .then((workout) => workout?.name ?? 'Workout'),
      programRepo
          .getById(instance.programId)
          .then((program) => program?.name ?? 'Program'),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor(context);
    final canOpen = instance.isScheduled || instance.isCompleted;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(_statusIcon(), color: color),
        title: FutureBuilder<List<String>>(
          future: _loadNames(ref),
          builder: (context, snapshot) {
            final names = snapshot.data ?? const ['Workout', 'Program'];
            return Text(workoutProgramLabel(names[0], names[1]));
          },
        ),
        subtitle: Text(workoutStatusLabel(instance.status)),
        trailing: instance.isScheduled
            ? FilledButton(
                onPressed: () =>
                    context.push('/athlete/workouts/${instance.id}'),
                child: const Text('Complete'),
              )
            : const Icon(Icons.chevron_right),
        onTap: canOpen
            ? () => context.push('/athlete/workouts/${instance.id}')
            : null,
      ),
    );
  }
}
