import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage3/core/enums.dart';
import 'package:stage3/features/auth/presentation/app_entry_providers.dart';
import 'package:stage3/features/auth/presentation/auth_providers.dart';
import 'package:stage3/features/programs/presentation/enrollment_providers.dart';
import 'package:stage3/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage3/features/workouts/presentation/workout_providers.dart';

/// Screen for assigning a workout to an athlete on a specific date.
///
/// The owner selects an enrolled athlete, a published workout, and a date.
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
      setState(() => _selectedDate = picked);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
              // Resolve athlete names
              final profileRepo = ref.read(userProfileRepositoryProvider);
              for (final e in enrollments) {
                if (!_athleteNames.containsKey(e.athleteId)) {
                  _athleteNames[e.athleteId] = e.athleteId;
                  profileRepo.getUserProfile(e.athleteId).then((profile) {
                    if (profile != null && mounted) {
                      setState(() {
                        _athleteNames[e.athleteId] =
                            profile.displayName;
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

          // Date picker
          Text(
            'Date',
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
                : const Icon(Icons.assignment_turned_in),
            label: const Text('Assign Workout'),
          ),
        ],
      ),
    );
  }
}
