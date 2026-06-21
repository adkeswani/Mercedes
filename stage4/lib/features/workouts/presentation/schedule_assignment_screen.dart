import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/auth/presentation/app_entry_providers.dart';
import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/programs/presentation/enrollment_providers.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';
import 'package:stage4/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage4/features/workouts/presentation/workout_providers.dart';

/// Screen for assigning a workout to an athlete on a specific date,
/// with optional recurrence for repeating schedules.
class ScheduleAssignmentScreen extends ConsumerStatefulWidget {
  const ScheduleAssignmentScreen({
    super.key,
    required this.programId,
    this.preselectedAthleteId,
  });

  final String programId;
  final String? preselectedAthleteId;

  @override
  ConsumerState<ScheduleAssignmentScreen> createState() =>
      _ScheduleAssignmentScreenState();
}

class _ScheduleAssignmentScreenState
    extends ConsumerState<ScheduleAssignmentScreen> {
  String? _selectedAthleteId;
  String? _selectedWorkoutId;
  int? _selectedWorkoutVersion;
  String? _selectedWorkoutName;
  WorkoutType? _selectedWorkoutType;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  bool _isLoading = false;
  final _athleteNames = <String, String>{};

  // Recurrence state
  bool _isRecurring = false;
  RecurrencePattern _recurrencePattern = RecurrencePattern.weekly;
  final Set<int> _selectedDays = {};
  int _intervalDays = 2;
  DateTime _endDate = DateTime.now().add(const Duration(days: 28));

  @override
  void initState() {
    super.initState();
    _selectedAthleteId = widget.preselectedAthleteId;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        // Keep end date at least on start date
        if (_endDate.isBefore(_selectedDate)) {
          _endDate = _selectedDate.add(const Duration(days: 28));
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _selectedDate,
      lastDate: _selectedDate.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  int _previewCount() {
    if (!_isRecurring) return 1;
    final days = _recurrencePattern == RecurrencePattern.weekly ||
            _recurrencePattern == RecurrencePattern.biweekly
        ? (_selectedDays.isEmpty ? null : _selectedDays.toList())
        : null;
    return expandRecurrence(
      startDate: _formatDate(_selectedDate),
      pattern: _recurrencePattern,
      endDate: _formatDate(_endDate),
      daysOfWeek: days,
      intervalDays: _recurrencePattern == RecurrencePattern.custom
          ? _intervalDays
          : null,
    ).length;
  }

  Future<void> _assign() async {
    if (_selectedAthleteId == null ||
        _selectedWorkoutId == null ||
        _selectedWorkoutVersion == null ||
        _selectedWorkoutType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an athlete and workout first')),
      );
      return;
    }

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(workoutInstanceRepositoryProvider);

      if (_isRecurring) {
        final days = _recurrencePattern == RecurrencePattern.weekly ||
                _recurrencePattern == RecurrencePattern.biweekly
            ? (_selectedDays.isEmpty ? null : _selectedDays.toList())
            : null;
        final recurrence = Recurrence(
          pattern: _recurrencePattern,
          daysOfWeek: days,
          intervalDays: _recurrencePattern == RecurrencePattern.custom
              ? _intervalDays
              : null,
          endDate: _formatDate(_endDate),
        );

        final count = await repo.assignRecurringWorkouts(
          programId: widget.programId,
          athleteId: _selectedAthleteId!,
          workoutTemplateId: _selectedWorkoutId!,
          workoutTemplateVersion: _selectedWorkoutVersion!,
          startDate: _formatDate(_selectedDate),
          workoutType: _selectedWorkoutType!,
          assignedBy: uid,
          recurrence: recurrence,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$count workouts scheduled')),
          );
          context.pop();
        }
      } else {
        await repo.assignWorkout(
          programId: widget.programId,
          athleteId: _selectedAthleteId!,
          workoutTemplateId: _selectedWorkoutId!,
          workoutTemplateVersion: _selectedWorkoutVersion!,
          scheduledDate: _formatDate(_selectedDate),
          workoutType: _selectedWorkoutType!,
          assignedBy: uid,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Workout scheduled for ${_formatDate(_selectedDate)}',
              ),
            ),
          );
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync =
        ref.watch(programEnrollmentsProvider(widget.programId));
    final workoutsAsync = ref.watch(workoutTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Assign Workout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Athlete picker
          Text(
            'Athlete',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          enrollmentsAsync.when(
            data: (enrollments) {
              if (enrollments.isEmpty) {
                return const Text('No athletes enrolled in this program');
              }
              final profileRepo = ref.read(userProfileRepositoryProvider);
              for (final e in enrollments) {
                if (!_athleteNames.containsKey(e.athleteId)) {
                  _athleteNames[e.athleteId] = e.athleteId;
                  profileRepo.getUserProfile(e.athleteId).then((profile) {
                    if (profile != null && mounted) {
                      setState(() {
                        _athleteNames[e.athleteId] = profile.displayName;
                      });
                    }
                  });
                }
              }
              return DropdownButtonFormField<String>(
                value: _selectedAthleteId,
                decoration:
                    const InputDecoration(labelText: 'Select athlete'),
                items: enrollments.map((e) {
                  return DropdownMenuItem(
                    value: e.athleteId,
                    child: Text(_athleteNames[e.athleteId] ?? e.athleteId),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedAthleteId = value);
                },
              );
            },
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
          ),

          const SizedBox(height: 24),

          // Workout picker
          Text(
            'Workout',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          workoutsAsync.when(
            data: (workouts) {
              final published =
                  workouts.where((w) => w.currentVersion > 0).toList();
              if (published.isEmpty) {
                return const Text('No published workouts available');
              }
              return DropdownButtonFormField<String>(
                value: _selectedWorkoutId,
                decoration:
                    const InputDecoration(labelText: 'Select workout'),
                items: published.map((w) {
                  return DropdownMenuItem(
                    value: w.id,
                    child: Text('${w.name} (v${w.currentVersion})'),
                  );
                }).toList(),
                onChanged: (value) {
                  final workout = published.firstWhere((w) => w.id == value);
                  setState(() {
                    _selectedWorkoutId = value;
                    _selectedWorkoutVersion = workout.currentVersion;
                    _selectedWorkoutName = workout.name;
                    _selectedWorkoutType = workout.workoutType;
                  });
                },
              );
            },
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
          ),

          const SizedBox(height: 24),

          // Start date picker
          Text(
            _isRecurring ? 'Start Date' : 'Date',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            title: Text(_formatDate(_selectedDate)),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Recurring toggle
          SwitchListTile(
            title: const Text('Recurring'),
            subtitle: const Text('Repeat on a schedule'),
            value: _isRecurring,
            onChanged: (value) => setState(() => _isRecurring = value),
          ),

          // Recurrence options (shown when recurring is on)
          if (_isRecurring) ...[
            const SizedBox(height: 16),

            // Pattern selector
            Text(
              'Pattern',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<RecurrencePattern>(
              segments: const [
                ButtonSegment(
                  value: RecurrencePattern.weekly,
                  label: Text('Weekly'),
                ),
                ButtonSegment(
                  value: RecurrencePattern.biweekly,
                  label: Text('Biweekly'),
                ),
                ButtonSegment(
                  value: RecurrencePattern.custom,
                  label: Text('Custom'),
                ),
              ],
              selected: {_recurrencePattern},
              onSelectionChanged: (selection) {
                setState(() => _recurrencePattern = selection.first);
              },
            ),

            const SizedBox(height: 16),

            // Days of week (for weekly/biweekly)
            if (_recurrencePattern == RecurrencePattern.weekly ||
                _recurrencePattern == RecurrencePattern.biweekly) ...[
              Text(
                'Days of Week',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'If none selected, uses the start date\'s day',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: List.generate(7, (index) {
                  final day = index + 1; // 1=Mon..7=Sun
                  return FilterChip(
                    label: Text(_dayLabels[index]),
                    selected: _selectedDays.contains(day),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDays.add(day);
                        } else {
                          _selectedDays.remove(day);
                        }
                      });
                    },
                  );
                }),
              ),
            ],

            // Interval days (for custom)
            if (_recurrencePattern == RecurrencePattern.custom) ...[
              Text(
                'Repeat every N days',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _intervalDays > 1
                        ? () => setState(() => _intervalDays--)
                        : null,
                  ),
                  Text(
                    '$_intervalDays',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _intervalDays < 30
                        ? () => setState(() => _intervalDays++)
                        : null,
                  ),
                  const Text(' days'),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // End date
            Text(
              'End Date',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ListTile(
              title: Text(_formatDate(_endDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickEndDate,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Preview count
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.event_repeat),
                    const SizedBox(width: 12),
                    Text(
                      '${_previewCount()} workouts will be created',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Assign button
          FilledButton.icon(
            onPressed: _isLoading ? null : _assign,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_isRecurring
                    ? Icons.event_repeat
                    : Icons.assignment_turned_in),
            label: Text(_isRecurring
                ? 'Schedule ${_previewCount()} Workouts'
                : 'Assign Workout'),
          ),
        ],
      ),
    );
  }
}
