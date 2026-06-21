import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/exercises/presentation/exercise_note_widget.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';
import 'package:stage4/features/workouts/domain/workout_template.dart';
import 'package:stage4/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage4/features/workouts/presentation/workout_providers.dart';

/// Screen for completing a scheduled workout.
///
/// The athlete enters RPE (1-10), duration, optional notes,
/// and per-exercise actuals before marking the workout as completed.
class WorkoutCompletionScreen extends ConsumerStatefulWidget {
  const WorkoutCompletionScreen({super.key, required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<WorkoutCompletionScreen> createState() =>
      _WorkoutCompletionScreenState();
}

class _WorkoutCompletionScreenState
    extends ConsumerState<WorkoutCompletionScreen> {
  final _notesController = TextEditingController();
  int _rpe = 5;
  int _durationMinutes = 45;
  bool _isLoading = false;
  WorkoutInstance? _instance;
  bool _didLoad = false;
  bool _isEditing = false;
  bool _isAthlete = false;
  List<ExercisePrescription> _exercises = [];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInstance() async {
    if (_didLoad) return;
    _didLoad = true;

    final repo = ref.read(workoutInstanceRepositoryProvider);
    final instance = await repo.getById(widget.instanceId);
    if (instance != null && mounted) {
      // Load exercises from the workout template
      final workoutRepo = ref.read(workoutTemplateRepositoryProvider);
      final exercises = await workoutRepo.getLatestExercises(
        instance.workoutTemplateId,
      );

      final uid = ref.read(authStateProvider).value?.uid;
      final isAthlete = uid == instance.athleteId;

      setState(() {
        _instance = instance;
        _exercises = exercises;
        _isAthlete = isAthlete;
        if (instance.isCompleted) {
          _isEditing = true;
          _rpe = instance.rpe ?? 5;
          _durationMinutes = instance.durationMinutes ?? 45;
          _notesController.text = instance.athleteNotes ?? '';
        }
      });
    }
  }

  Future<void> _complete() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(workoutInstanceRepositoryProvider);
      if (_isEditing) {
        await repo.updateCompletion(
          instanceId: widget.instanceId,
          rpe: _rpe,
          durationMinutes: _durationMinutes,
          actuals: [],
          athleteNotes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await repo.completeWorkout(
          instanceId: widget.instanceId,
          rpe: _rpe,
          durationMinutes: _durationMinutes,
          actuals: [],
          athleteNotes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Workout updated!' : 'Workout completed! 💪'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_didLoad) _loadInstance();

    if (_instance == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Complete Workout')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final instance = _instance!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAthlete
            ? (_isEditing ? 'Edit Workout' : 'Complete Workout')
            : 'Workout Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Workout info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instance.workoutType.name.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Scheduled: ${instance.scheduledDate}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Exercises with personal notes
          if (_exercises.isNotEmpty) ...[
            Text(
              'Exercises',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._exercises.map((exercise) {
              final summary = _prescriptionSummary(exercise);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.exerciseName ?? exercise.exerciseId,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_isAthlete)
                        ExerciseNoteWidget(
                        exerciseTemplateId: exercise.exerciseId,
                        exerciseName:
                            exercise.exerciseName ?? exercise.exerciseId,
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
          ] else
            const SizedBox(height: 24),

          // RPE slider
          if (_isAthlete) ...[
            Text(
              'Rate of Perceived Exertion (RPE)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '$_rpe',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _rpeColor(_rpe),
                      ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Slider(
                    value: _rpe.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$_rpe',
                    onChanged: (value) {
                      setState(() => _rpe = value.round());
                    },
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('1 (Easy)', style: Theme.of(context).textTheme.bodySmall),
                Text('10 (Max)', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),

            const SizedBox(height: 24),

            // Duration
            Text(
              'Duration (minutes)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _durationMinutes > 5
                      ? () => setState(() => _durationMinutes -= 5)
                      : null,
                ),
                Text(
                  '$_durationMinutes min',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _durationMinutes += 5),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Notes
            Text(
              'Notes (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                hintText: 'How did it go?',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),

            const SizedBox(height: 32),

            // Complete button
            FilledButton.icon(
              onPressed: _isLoading ? null : _complete,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_isEditing ? Icons.save : Icons.check_circle),
              label: Text(_isEditing ? 'Save Changes' : 'Mark as Completed'),
            ),
          ] else if (instance.isCompleted) ...[
            // Read-only view for owner
            Text(
              'Completion Details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('RPE: ',
                            style: Theme.of(context).textTheme.bodyMedium),
                        Text(
                          '${instance.rpe ?? '-'}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _rpeColor(instance.rpe ?? 5),
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Duration: ${instance.durationMinutes ?? '-'} min',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (instance.athleteNotes != null &&
                        instance.athleteNotes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Athlete notes: ${instance.athleteNotes}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ] else ...[
            // Owner viewing a scheduled workout — no actions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'This workout is scheduled for the athlete. '
                  'Only the athlete can complete it.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _prescriptionSummary(ExercisePrescription exercise) {
    final parts = <String>[];
    parts.add(exercise.mode.name);
    if (exercise.sets != null) parts.add('${exercise.sets} sets');
    if (exercise.reps != null) parts.add('${exercise.reps} reps');
    if (exercise.durationSeconds != null) {
      parts.add('${exercise.durationSeconds}s');
    }
    if (exercise.weight != null) parts.add(exercise.weight!);
    return parts.join(' · ');
  }

  Color _rpeColor(int rpe) {
    if (rpe <= 3) return Colors.green;
    if (rpe <= 6) return Colors.orange;
    return Colors.red;
  }
}
