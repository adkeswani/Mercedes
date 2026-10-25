import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_media_widgets.dart';
import 'package:stage5/features/exercises/presentation/exercise_note_widget.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/workouts/data/workout_completion_draft_repository.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_timer_widget.dart';

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
  List<WorkoutBlock> _blocks = [];
  final Map<String, ExerciseActual> _actuals = {};
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
        final currentClientId = ref.read(workoutDraftClientIdProvider);
        restore = await ref.read(workoutCompletionDraftRepositoryProvider).load(
              instanceId: instance.id,
              athleteId: uid,
              currentClientId: currentClientId,
            );
      }
      if (!mounted || widget.instanceId != instance.id) {
        return;
      }
      setState(() {
        _instance = instance;
        _blocks = workoutVersion?.blocks ?? [];
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
    try {
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
            final authoritative = result.authoritativeDraft;
            if (authoritative != null &&
                authoritative.clientId == draft.clientId &&
                compareWorkoutDrafts(authoritative, draft) > 0) {
              _restoring = true;
              _revision = authoritative.revision;
              _rpe = authoritative.rpe;
              _durationMinutes = authoritative.durationMinutes;
              _notesController.text = authoritative.athleteNotes ?? '';
              _restoring = false;
              _recoveryMessage = 'Restored saved workout progress.';
            }
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

  void _onActualChanged(ExerciseActual actual) {
    _actuals[actual.slotId] = actual;
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
        actuals: _actuals.values.toList(),
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
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/athlete/today');
        }
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

          // Exercises with media, instructions, and recorded actuals
          if (_blocks.isNotEmpty) ...[
            Text(
              'Exercises',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final block in _blocks) ...[
              if (_blockSummary(block) != null) ...[
                Text(
                  _blockSummary(block)!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 4),
              ],
              for (final slot in block.slots)
                _ExerciseEntryCard(
                  key: ValueKey(slot.slotId),
                  slot: slot,
                  block: block,
                  isAthlete: _isAthlete,
                  recordingEnabled:
                      _isAthlete && !instance.isCompleted,
                  onActualChanged: _onActualChanged,
                ),
            ],
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

  Color _rpeColor(int rpe) {
    if (rpe <= 3) {
      return Colors.green;
    }
    if (rpe <= 6) {
      return Colors.orange;
    }
    return Colors.red;
  }

  /// Block-level summary shown above a block's exercise card(s): the
  /// climbing route's grade/color, or an interval/circuit's rounds and
  /// timing. Returns null for a plain standard exercise block, since its
  /// card already shows the prescription summary.
  String? _blockSummary(WorkoutBlock block) {
    return switch (block) {
      ClimbingRouteBlock(:final grade, :final color, :final targetAttempts) =>
        'Climbing route · Grade $grade · $color'
            '${targetAttempts != null ? ' · Target $targetAttempts attempts' : ''}',
      TimedIntervalBlock(:final rounds, :final workSeconds, :final restSeconds) =>
        '$rounds rounds · ${workSeconds}s work / ${restSeconds}s rest',
      CircuitBlock(:final rounds, :final restBetweenRoundsSeconds) =>
        '$rounds rounds · ${restBetweenRoundsSeconds}s rest between rounds',
      StandardExerciseBlock() => null,
    };
  }
}

/// Human-readable summary of a slot's prescribed sets/reps/duration/weight.
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

/// A collapsible card for one prescribed exercise shown while completing a
/// workout. Defaults to expanded, showing the exercise's video, description,
/// and instructions inline, plus mode-aware fields for recording what the
/// athlete actually did (reps/sets/weight, duration, or climbing attempts and
/// send status, depending on the block type).
class _ExerciseEntryCard extends ConsumerStatefulWidget {
  const _ExerciseEntryCard({
    required this.slot,
    required this.block,
    required this.isAthlete,
    required this.recordingEnabled,
    required this.onActualChanged,
    super.key,
  });

  final ExerciseSlot slot;
  final WorkoutBlock block;
  final bool isAthlete;

  /// Whether to show actual-recording inputs (the athlete is completing a
  /// still-scheduled workout) rather than a read-only view.
  final bool recordingEnabled;
  final ValueChanged<ExerciseActual> onActualChanged;

  @override
  ConsumerState<_ExerciseEntryCard> createState() =>
      _ExerciseEntryCardState();
}

class _ExerciseEntryCardState extends ConsumerState<_ExerciseEntryCard> {
  bool _expanded = true;
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;
  late final TextEditingController _durationController;
  late final TextEditingController _attemptsController;
  bool _sent = false;
  int? _restElapsedSeconds;

  bool get _isClimbing => widget.block is ClimbingRouteBlock;
  bool get _isTimed =>
      widget.block is TimedIntervalBlock ||
      widget.slot.mode == ExerciseMode.time;

  /// Prescribed work-interval length to count down from, if known:
  /// prefers an explicit slot duration, then a timed-interval block's
  /// per-round work length.
  int? get _workTargetSeconds {
    final slot = widget.slot;
    if (slot.durationSeconds != null) {
      return slot.durationSeconds;
    }
    final block = widget.block;
    if (block is TimedIntervalBlock) {
      return block.workSeconds;
    }
    return null;
  }

  /// Prescribed rest length to count down from, if known: an explicit slot
  /// rest, a timed-interval block's rest, or a circuit's rest between
  /// rounds.
  int? get _restTargetSeconds {
    final slot = widget.slot;
    if (slot.restSeconds != null) {
      return slot.restSeconds;
    }
    final block = widget.block;
    if (block is TimedIntervalBlock) {
      return block.restSeconds;
    }
    if (block is CircuitBlock && block.restBetweenRoundsSeconds > 0) {
      return block.restBetweenRoundsSeconds;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final slot = widget.slot;
    _setsController = TextEditingController(text: slot.sets?.toString() ?? '');
    _repsController = TextEditingController(text: slot.reps ?? '');
    _weightController = TextEditingController(text: slot.weight ?? '');
    _durationController = TextEditingController(
      text: slot.durationSeconds?.toString() ?? '',
    );
    final targetAttempts = widget.block is ClimbingRouteBlock
        ? (widget.block as ClimbingRouteBlock).targetAttempts
        : null;
    _attemptsController = TextEditingController(
      text: targetAttempts?.toString() ?? '',
    );
    if (widget.recordingEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emitActual());
    }
  }

  @override
  void dispose() {
    _setsController.dispose();
    _repsController.dispose();
    _weightController.dispose();
    _durationController.dispose();
    _attemptsController.dispose();
    super.dispose();
  }

  void _emitActual() {
    final slot = widget.slot;
    widget.onActualChanged(
      ExerciseActual(
        exerciseId: slot.exerciseId,
        mode: slot.mode,
        slotId: slot.slotId,
        sets: _isClimbing || _isTimed ? null : int.tryParse(_setsController.text),
        reps: _isClimbing || _isTimed
            ? null
            : (_repsController.text.trim().isEmpty
                ? null
                : _repsController.text.trim()),
        durationSeconds:
            _isTimed ? int.tryParse(_durationController.text) : null,
        weight: _isClimbing || _isTimed
            ? null
            : (_weightController.text.trim().isEmpty
                ? null
                : _weightController.text.trim()),
        attempts: _isClimbing ? int.tryParse(_attemptsController.text) : null,
        sent: _isClimbing ? _sent : null,
        restSeconds: _restElapsedSeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slot = widget.slot;
    final exerciseVersion = ref.watch(
      exerciseVersionByIdProvider(
        ExerciseVersionKey(slot.exerciseId, slot.exerciseVersion),
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      slot.exerciseName ?? slot.exerciseId,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: 'View full exercise details',
                    onPressed: () => context.push(
                      '/exercises/${slot.exerciseId}'
                      '?version=${slot.exerciseVersion}',
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
            if (!_isClimbing) ...[
              const SizedBox(height: 2),
              Text(
                _prescriptionSummary(slot),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: 8),
              exerciseVersion.when(
                data: (version) => _ExerciseContent(version: version),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (error, stackTrace) => const SizedBox.shrink(),
              ),
              if (widget.recordingEnabled) ...[
                const SizedBox(height: 12),
                const Divider(),
                Text('Record actual', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                _buildActualInputs(),
                if (_restTargetSeconds != null) ...[
                  const SizedBox(height: 8),
                  WorkoutTimerWidget(
                    key: ValueKey('rest-timer-${slot.slotId}'),
                    label: 'Rest',
                    targetSeconds: _restTargetSeconds,
                    onElapsedChanged: (seconds) {
                      _restElapsedSeconds = seconds;
                      _emitActual();
                    },
                  ),
                ],
              ],
              if (widget.isAthlete) ...[
                const SizedBox(height: 8),
                ExerciseNoteWidget(
                  exerciseTemplateId: slot.exerciseId,
                  exerciseName: slot.exerciseName ?? slot.exerciseId,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActualInputs() {
    if (_isClimbing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _attemptsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Attempts',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _emitActual(),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _sent,
            onChanged: (value) {
              setState(() => _sent = value ?? false);
              _emitActual();
            },
            title: const Text('Sent the route'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      );
    }
    if (_isTimed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkoutTimerWidget(
            key: ValueKey('work-timer-${widget.slot.slotId}'),
            label: 'Work',
            targetSeconds: _workTargetSeconds,
            onElapsedChanged: (seconds) {
              _durationController.text = seconds.toString();
              _emitActual();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Duration (seconds)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _emitActual(),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _setsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Sets',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _emitActual(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _repsController,
            decoration: const InputDecoration(
              labelText: 'Reps',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _emitActual(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _weightController,
            decoration: const InputDecoration(
              labelText: 'Weight',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _emitActual(),
          ),
        ),
      ],
    );
  }
}

/// Renders an exercise version's video, description, and (length-limited,
/// scrollable) instructions.
class _ExerciseContent extends StatelessWidget {
  const _ExerciseContent({required this.version});

  final ExerciseVersion? version;

  @override
  Widget build(BuildContext context) {
    final version = this.version;
    if (version == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final videoUrl = version.videoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (videoUrl != null && videoUrl.trim().isNotEmpty) ...[
          ExerciseVideoPreview(url: videoUrl.trim()),
          const SizedBox(height: 8),
        ],
        if (version.description.trim().isNotEmpty) ...[
          Text(version.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
        ],
        if (version.instructions.trim().isNotEmpty) ...[
          Text('Instructions', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          BoundedScrollableText(
            version.instructions,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

