import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage3/core/enums.dart';
import 'package:stage3/features/workouts/domain/workout_instance.dart';
import 'package:stage3/features/workouts/presentation/workout_instance_providers.dart';

/// Calendar-style schedule view for athletes.
///
/// Shows a week-at-a-time view of scheduled, completed, and missed workouts
/// with color-coded status indicators.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Start on Monday of the current week
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
  }

  void _previousWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
    });
  }

  String _formatIsoDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatShortDate(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]} ${date.month}/${date.day}';
  }

  String _formatWeekRange() {
    final end = _weekStart.add(const Duration(days: 6));
    return '${_weekStart.month}/${_weekStart.day} - ${end.month}/${end.day}';
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final range = DateRange(
      startDate: _formatIsoDate(_weekStart),
      endDate: _formatIsoDate(weekEnd),
    );
    final scheduleAsync = ref.watch(athleteScheduleProvider(range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Schedule'),
      ),
      body: Column(
        children: [
          // Week navigation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _previousWeek,
                ),
                Text(
                  _formatWeekRange(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextWeek,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Day-by-day schedule
          Expanded(
            child: scheduleAsync.when(
              data: (instances) => _buildWeekView(context, instances),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekView(
    BuildContext context,
    List<WorkoutInstance> instances,
  ) {
    // Group instances by date
    final byDate = <String, List<WorkoutInstance>>{};
    for (final instance in instances) {
      byDate.putIfAbsent(instance.scheduledDate, () => []).add(instance);
    }

    return ListView.builder(
      itemCount: 7,
      itemBuilder: (context, index) {
        final day = _weekStart.add(Duration(days: index));
        final dateKey = _formatIsoDate(day);
        final dayInstances = byDate[dateKey] ?? [];
        final isToday = _formatIsoDate(DateTime.now()) == dateKey;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header
            Container(
              color: isToday
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    _formatShortDate(day),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Today',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
                                ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Workout instances for this day
            if (dayInstances.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Rest day',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              )
            else
              ...dayInstances.map((instance) {
                return _WorkoutInstanceTile(instance: instance);
              }),

            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

class _WorkoutInstanceTile extends ConsumerWidget {
  const _WorkoutInstanceTile({required this.instance});

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
    final color = _statusColor(context);

    return ListTile(
      leading: Icon(_statusIcon(), color: color),
      title: Text(instance.workoutTemplateId),
      subtitle: Text(
        '${instance.workoutType.name} · ${instance.status.name}'
        '${instance.rpe != null ? ' · RPE ${instance.rpe}' : ''}',
      ),
      trailing: instance.isScheduled
          ? FilledButton(
              onPressed: () => context.push(
                '/workouts/complete/${instance.id}',
              ),
              child: const Text('Complete'),
            )
          : instance.isCompleted
              ? const Icon(Icons.chevron_right)
              : null,
      onTap: (instance.isScheduled || instance.isCompleted)
          ? () => context.push('/workouts/complete/${instance.id}')
          : null,
    );
  }
}
