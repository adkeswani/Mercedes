import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/presentation/exercise_note_widget.dart';
import 'package:stage5/features/workouts/data/workout_completion_draft_repository.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

/// Screen for completing a scheduled workout.
///
/// The athlete enters RPE (1-10), duration, optional notes,
/// and per-exercise actuals before marking the workout as completed.
class WorkoutCompletionScreen extends ConsumerStatefulWidget {
  const WorkoutCompletionScreen({required this.instanceId, super.key});

  final String instanceId;

  @override
  ConsumerState<WorkoutCompletionScreen> createState() =>
      _WorkoutCompletionScreenState();
}

class _WorkoutCompletionScreenState
    extends ConsumerState<WorkoutCompletionScreen> with WidgetsBindingObserver {
  final _notesController = TextEditingController();
  int _rpe = 5;
  int _durationMinutes = 45;
  bool _isLoading = false;
  WorkoutInstance? _instance;
  bool _isAthlete = false;
  List<ExerciseSlot> _exercises = [];
  _WorkoutLoadState _loadState = _WorkoutLoadState.loading;
  _DraftSaveState _saveState = _DraftSaveState.saved;
  Timer? _saveDebounce;
  int _revision = 0;
  bool _restoring = true;
  String? _recoveryMessage;
  String? _loadMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notesController.addListener(_scheduleSave);
    _loadInstance();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    _notesController.removeListener(_scheduleSave);
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDebounce?.cancel();
      unawaited(_saveDraft());
    }
  }

  Future<void> _loadInstance() async {
    try {
      final repo = ref.read(workoutInstanceRepositoryProvider);
      final instance = await repo.getById(widget.instanceId);
      if (instance == null) {
        if (mounted) {
          setState(() => _loadState = _WorkoutLoadState.notFound);
        }
        return;
      }
      final uid = ref.read(authStateProvider).value?.uid;
      if (uid == null) {
        throw StateError('A signed-in user is required');
      }
      final isAthlete = uid == instance.athleteId;
      if (!isAthlete && !instance.isCompleted) {
        if (mounted) {
          setState(() {
            _instance = instance;
            _loadState = _WorkoutLoadState.unauthorized;
          });
        }
        return;
      }

      final workoutRepo = ref.read(workoutTemplateRepositoryProvider);
      final workoutVersion = await workoutRepo.getVersion(
        instance.workoutTemplateId,
        instance.workoutTemplateVersion,
      );

      WorkoutDraftRestoreResult? restore;
      if (isAthlete && instance.isScheduled) {
        restore = await ref
            .read(workoutCompletionDraftRepositoryProvider)
            .load(instanceId: instance.id, athleteId: uid);
      }
      if (!mounted || widget.instanceId != instance.id) {
        return;
      }
      setState(() {
        _instance = instance;
        _exercises = workoutVersion?.exerciseSlots ?? [];
        _isAthlete = isAthlete;
        final draft = restore?.draft;
        if (draft != null) {
          _rpe = draft.rpe;
          _durationMinutes = draft.durationMinutes;
          _notesController.text = draft.athleteNotes ?? '';
          _revision = draft.revision;
          _recoveryMessage = restore?.message;
        } else if (instance.isCompleted) {
          _rpe = instance.rpe ?? 5;
          _durationMinutes = instance.durationMinutes ?? 45;
          _notesController.text = instance.athleteNotes ?? '';
        } else if (restore?.message != null) {
          _recoveryMessage = restore!.message;
        }
        if (restore?.deviceOnly == true) {
          _saveState = _DraftSaveState.offline;
        }
        _loadState = _WorkoutLoadState.ready;
        _restoring = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadState = _WorkoutLoadState.error;
          _loadMessage = error.toString();
          _restoring = false;
        });
      }
    }
  }

  void _scheduleSave() {
    if (_restoring ||
        !_isAthlete ||
        _instance?.isScheduled != true ||
        _isLoading) {
      return;
    }
    _saveDebounce?.cancel();
    setState(() => _saveState = _DraftSaveState.saving);
    _saveDebounce = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final instance = _instance;
    final athleteId = ref.read(authStateProvider).value?.uid;
    if (instance == null ||
        athleteId == null ||
        !instance.isScheduled ||
        !_isAthlete ||
        _isLoading) {
      return;
    }
    final revision = ++_revision;
    final route = '/athlete/workouts/${instance.id}';
    final draft = WorkoutCompletionDraft(
      instanceId: instance.id,
      athleteId: athleteId,
      rpe: _rpe,
      durationMinutes: _durationMinutes,
      athleteNotes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      revision: revision,
      clientId: ref.read(workoutDraftClientIdProvider),
      updatedAt: DateTime.now().toUtc(),
      sourceRoute: route,
    );
    try {
      final result =
          await ref.read(workoutCompletionDraftRepositoryProvider).save(draft);
      if (!mounted ||
          widget.instanceId != instance.id ||
          revision != _revision ||
          _isLoading) {
        return;
      }
      setState(() {
        switch (result.status) {
          case WorkoutDraftSaveStatus.saved:
            _saveState = _DraftSaveState.saved;
          case WorkoutDraftSaveStatus.offline:
            _saveState = _DraftSaveState.offline;
          case WorkoutDraftSaveStatus.conflict:
            _saveState = _DraftSaveState.conflict;
            final authoritative = result.authoritativeDraft;
            if (authoritative != null) {
              _restoring = true;
              _revision = authoritative.revision;
              _rpe = authoritative.rpe;
              _durationMinutes = authoritative.durationMinutes;
              _notesController.text = authoritative.athleteNotes ?? '';
              _restoring = false;
              _recoveryMessage =
                  'Another tab saved newer progress. Its draft was restored.';
            }
        }
      });
    } catch (_) {
      if (mounted &&
          widget.instanceId == instance.id &&
          revision == _revision &&
          !_isLoading) {
        setState(() => _saveState = _DraftSaveState.failed);
      }
    }
  }

  Future<void> _complete() async {
    _saveDebounce?.cancel();
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(workoutInstanceRepositoryProvider);
      final athleteId = ref.read(authStateProvider).value?.uid;
      if (athleteId == null) {
        throw StateError('A signed-in athlete is required');
      }
      await repo.completeWorkout(
        instanceId: widget.instanceId,
        athleteId: athleteId,
        rpe: _rpe,
        durationMinutes: _durationMinutes,
        actuals: [],
        athleteNotes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      await ref
          .read(workoutCompletionDraftRepositoryProvider)
          .clearLocalAfterCompletion(
            instanceId: widget.instanceId,
            athleteId: athleteId,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workout completed! 💪')),
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadState != _WorkoutLoadState.ready) {
      return _buildLoadState();
    }

    final instance = _instance!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isAthlete && !instance.isCompleted
              ? 'Complete Workout'
              : 'Workout Details',
        ),
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
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push(
                    '/exercises/${exercise.exerciseId}'
                    '?version=${exercise.exerciseVersion}',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                exercise.exerciseName ?? exercise.exerciseId,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ],
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
                ),
              );
            }),
            const SizedBox(height: 24),
          ] else
            const SizedBox(height: 24),

          // RPE slider
          if (_isAthlete && !instance.isCompleted) ...[
            if (_recoveryMessage != null) ...[
              MaterialBanner(
                content: Text(_recoveryMessage!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _recoveryMessage = null),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _DraftSaveStatus(
              state: _saveState,
              onRetry: _saveState == _DraftSaveState.failed ? _saveDraft : null,
            ),
            const SizedBox(height: 16),
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
                      _scheduleSave();
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
                      ? () {
                          setState(() => _durationMinutes -= 5);
                          _scheduleSave();
                        }
                      : null,
                ),
                Text(
                  '$_durationMinutes min',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    setState(() => _durationMinutes += 5);
                    _scheduleSave();
                  },
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
                  : const Icon(Icons.check_circle),
              label: const Text('Mark as Completed'),
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
                        Text(
                          'RPE: ',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          '${instance.rpe ?? '-'}',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
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

  Widget _buildLoadState() {
    final (icon, title, detail) = switch (_loadState) {
      _WorkoutLoadState.loading => (
          null,
          'Loading workout',
          'Restoring your workout and saved progress...',
        ),
      _WorkoutLoadState.notFound => (
          Icons.search_off,
          'Workout not found',
          'This workout may have been removed or the link is invalid.',
        ),
      _WorkoutLoadState.unauthorized => (
          Icons.lock_outline,
          'Workout unavailable',
          'Only the assigned athlete can open this in-progress workout.',
        ),
      _WorkoutLoadState.error => (
          Icons.error_outline,
          'Could not load workout',
          _loadMessage ?? 'Check your connection and try again.',
        ),
      _WorkoutLoadState.ready => (null, '', ''),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Workout')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadState == _WorkoutLoadState.loading)
                const CircularProgressIndicator()
              else
                Icon(icon, size: 48),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
              if (_loadState == _WorkoutLoadState.error) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() => _loadState = _WorkoutLoadState.loading);
                    _loadInstance();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _prescriptionSummary(ExerciseSlot exercise) {
    final parts = <String>[];
    parts.add(exercise.mode.name);
    if (exercise.sets != null) {
      parts.add('${exercise.sets} sets');
    }
    if (exercise.reps != null) {
      parts.add('${exercise.reps} reps');
    }
    if (exercise.durationSeconds != null) {
      parts.add('${exercise.durationSeconds}s');
    }
    if (exercise.weight != null) {
      parts.add(exercise.weight!);
    }
    return parts.join(' · ');
  }

  Color _rpeColor(int rpe) {
    if (rpe <= 3) {
      return Colors.green;
    }
    if (rpe <= 6) {
      return Colors.orange;
    }
    return Colors.red;
  }
}

enum _WorkoutLoadState { loading, ready, notFound, unauthorized, error }

enum _DraftSaveState { saving, saved, offline, failed, conflict }

class _DraftSaveStatus extends StatelessWidget {
  const _DraftSaveStatus({required this.state, this.onRetry});

  final _DraftSaveState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state) {
      _DraftSaveState.saving => (
          Icons.sync,
          'Saving...',
          Theme.of(context).colorScheme.primary,
        ),
      _DraftSaveState.saved => (
          Icons.cloud_done_outlined,
          'Saved',
          Colors.green,
        ),
      _DraftSaveState.offline => (
          Icons.cloud_off_outlined,
          'Offline — saved on this device',
          Colors.orange,
        ),
      _DraftSaveState.failed => (
          Icons.error_outline,
          'Save failed',
          Theme.of(context).colorScheme.error,
        ),
      _DraftSaveState.conflict => (
          Icons.merge_type,
          'Newer progress restored',
          Colors.orange,
        ),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color)),
        if (onRetry != null) ...[
          const Spacer(),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    );
  }
}
