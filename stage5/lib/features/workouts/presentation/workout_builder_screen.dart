import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_organizer.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/exercise_picker.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

/// Builder screen for creating/editing a workout template.
///
/// Collects header info (name, workout type) and manages a local draft
/// of exercise prescriptions. Changes are only persisted on Publish.
class WorkoutBuilderScreen extends ConsumerStatefulWidget {
  const WorkoutBuilderScreen({super.key, this.workoutId, this.copyFromId});

  final String? workoutId;

  /// When set, pre-populates the draft with exercises from this template.
  final String? copyFromId;

  bool get isEditing => workoutId != null;

  @override
  ConsumerState<WorkoutBuilderScreen> createState() =>
      _WorkoutBuilderScreenState();
}

class _WorkoutBuilderScreenState extends ConsumerState<WorkoutBuilderScreen> {
  final _nameController = TextEditingController();
  WorkoutType _workoutType = WorkoutType.fullBody;
  bool _isLoading = false;
  bool _didLoad = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Clear draft when entering the builder
    Future.microtask(() {
      ref.read(workoutDraftProvider.notifier).clear();
    });
  }

  @override
  void didUpdateWidget(covariant WorkoutBuilderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutId == widget.workoutId &&
        oldWidget.copyFromId == widget.copyFromId) {
      return;
    }
    _didLoad = true;
    _nameController.clear();
    _workoutType = WorkoutType.fullBody;
    final workoutId = widget.workoutId;
    Future.microtask(() {
      if (!mounted || widget.workoutId != workoutId) return;
      ref.read(workoutDraftProvider.notifier).clear();
      _didLoad = false;
      _loadExisting();
    });
  }

  Future<void> _loadExisting() async {
    if (_didLoad || !widget.isEditing) return;
    _didLoad = true;

    final repo = ref.read(workoutTemplateRepositoryProvider);
    final workoutId = widget.workoutId!;
    final template = await repo.getById(workoutId);
    if (template == null || !mounted || widget.workoutId != workoutId) return;

    _nameController.text = template.name;
    setState(() => _workoutType = template.workoutType);

    // If duplicating from another template, load its exercises
    final source = resolveLibraryEditorSource(
      targetTemplateId: workoutId,
      targetVersion: template.currentVersion,
      routeSourceTemplateId: widget.copyFromId,
      provenance: template.provenance,
    );
    final sourceVersion = source.version ??
        (await repo.getById(source.templateId))?.currentVersion ??
        0;
    final savedDraft = await repo.getSavedDraft(workoutId);
    if (savedDraft != null && mounted && widget.workoutId == workoutId) {
      ref.read(workoutDraftProvider.notifier).load(savedDraft);
    } else if (sourceVersion > 0) {
      final version = await repo.getVersion(
        source.templateId,
        sourceVersion,
      );
      if (version != null && mounted && widget.workoutId == workoutId) {
        ref.read(workoutDraftProvider.notifier).load(version.blocks);
      }
    }
  }

  Future<void> _createAndEnter() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    // Check for duplicate name
    final existing = ref.read(workoutTemplatesProvider).valueOrNull ?? [];
    if (existing.any((w) => w.name == name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A workout with that name already exists'),
          ),
        );
      }
      return;
    }

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(workoutTemplateRepositoryProvider);
      final id = await repo.create(
        name: name,
        workoutType: _workoutType,
        userId: uid,
      );
      if (mounted) {
        // Replace the /workouts/new route with /workouts/:id
        context.pushReplacement('/workouts/$id');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveHeader() async {
    if (!widget.isEditing) return;
    if (_nameController.text.trim().isEmpty) return;

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final repo = ref.read(workoutTemplateRepositoryProvider);
    await repo.update(
      id: widget.workoutId!,
      name: _nameController.text.trim(),
      workoutType: _workoutType,
      userId: uid,
    );
  }

  Future<void> _publish() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final templateId = widget.workoutId!;
    final blocks = ref.read(workoutDraftProvider);
    final draftRevision = ref.read(workoutDraftProvider.notifier).revision;
    if (blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise first')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Save header changes first
      await _saveHeader();

      final repo = ref.read(workoutTemplateRepositoryProvider);
      final version = await repo.publishVersion(
        templateId: templateId,
        blocks: blocks,
        userId: uid,
      );

      if (mounted) {
        if (widget.workoutId == templateId &&
            ref.read(workoutDraftProvider.notifier).revision == draftRevision) {
          ref.read(workoutDraftProvider.notifier).markSaved();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Published version $version')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDraft() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    final templateId = widget.workoutId!;
    final blocks = ref.read(workoutDraftProvider);
    final draftRevision = ref.read(workoutDraftProvider.notifier).revision;
    if (blocks.isEmpty) {
      _showMessage('Add at least one exercise first');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _saveHeader();
      await ref.read(workoutTemplateRepositoryProvider).saveDraft(
            templateId: templateId,
            blocks: blocks,
            userId: uid,
          );
      if (mounted &&
          widget.workoutId == templateId &&
          ref.read(workoutDraftProvider.notifier).revision == draftRevision) {
        ref.read(workoutDraftProvider.notifier).markSaved();
      }
      if (mounted) {
        _showMessage('Draft saved. Publishing is still required.');
      }
    } catch (error) {
      if (mounted) _showMessage('Failed to save draft: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _discardDraft() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    final confirmed = await _confirmDiscard();
    if (!confirmed) return;
    await ref.read(workoutTemplateRepositoryProvider).discardDraft(
          templateId: widget.workoutId!,
          userId: uid,
        );
    final template = await ref
        .read(workoutTemplateRepositoryProvider)
        .getById(widget.workoutId!);
    final version = template != null && template.currentVersion > 0
        ? await ref
            .read(workoutTemplateRepositoryProvider)
            .getVersion(template.id, template.currentVersion)
        : null;
    ref.read(workoutDraftProvider.notifier).load(version?.blocks ?? const []);
    if (mounted) _showMessage('Draft changes discarded');
  }

  Future<bool> _confirmDiscard() async {
    if (!ref.read(workoutDraftProvider.notifier).isDirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text(
              'Your last saved draft and published versions will remain.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _addLibraryExercise(ExerciseTemplate exercise, {int? index}) {
    try {
      ref.read(workoutDraftProvider.notifier).addLibraryExercise(
            exerciseId: exercise.id,
            exerciseVersion: exercise.currentVersion,
            exerciseName: exercise.name,
            index: index,
          );
    } on Object catch (error) {
      _showMessage('$error');
    }
  }

  Future<void> _deleteWorkout() async {
    final repo = ref.read(workoutTemplateRepositoryProvider);
    final referenced = await repo.isWorkoutReferenced(widget.workoutId!);
    if (referenced) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cannot delete — this workout is used in a program',
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workout template?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    await ref.read(workoutTemplateRepositoryProvider).softDelete(
          widget.workoutId!,
          uid,
        );
    if (mounted) context.pop();
  }

  void _addExercise() async {
    final result = await showExercisePicker(context, ref);
    if (result == null) return;

    final blocks = ref.read(workoutDraftProvider);
    final slotCount =
        blocks.fold<int>(0, (count, block) => count + block.slots.length);
    if (slotCount >= maxExercisePrescriptionsPerWorkoutVersion) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A workout supports up to 9 exercises')),
        );
      }
      return;
    }
    final repo = ref.read(workoutTemplateRepositoryProvider);
    ref.read(workoutDraftProvider.notifier).addExercise(
          blockId: repo.generateWorkoutBlockId(),
          slot: ExerciseSlot(
            slotId: repo.generateExerciseSlotId(),
            exerciseId: result.id,
            exerciseVersion: result.version,
            exerciseName: result.name,
            sortOrder: 0,
            mode: ExerciseMode.reps,
            sets: 3,
            reps: '8-12',
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    // Load existing template on first build
    if (widget.isEditing && !_didLoad) {
      _loadExisting();
    }

    final blocks = ref.watch(workoutDraftProvider);

    // New template — show creation form
    if (!widget.isEditing) {
      return _buildCreationForm();
    }

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Workout Builder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last canvas change',
            onPressed: ref.read(workoutDraftProvider.notifier).canUndo
                ? ref.read(workoutDraftProvider.notifier).undo
                : null,
          ),
          TextButton(
            onPressed: _isLoading ? null : _saveDraft,
            child: const Text('Save draft'),
          ),
          TextButton(
            onPressed: _isLoading ? null : _discardDraft,
            child: const Text('Discard'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete workout',
            onPressed: _isLoading ? null : _deleteWorkout,
          ),
          TextButton(
            onPressed: _isLoading ? null : _publish,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Publish'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final canvas = _buildWorkoutCanvas(blocks);
          if (constraints.maxWidth < 900) {
            return canvas;
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: constraints.maxWidth * .36,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: _buildExerciseLibrary(),
                ),
              ),
              Expanded(child: canvas),
            ],
          );
        },
      ),
    );
    return WillPopScope(
      onWillPop: _confirmDiscard,
      child: scaffold,
    );
  }

  Widget _buildExerciseLibrary() {
    final exercisesAsync = ref.watch(exerciseTemplatesProvider);
    final foldersAsync = ref.watch(
      libraryFoldersProvider(LibraryItemType.exercise),
    );
    final userId = ref.watch(authStateProvider).valueOrNull?.uid;
    if (userId == null) {
      return const Center(child: Text('Sign in to view exercises.'));
    }
    return exercisesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => LibraryLoadError(
        message: 'Could not load exercises: $error',
        onRetry: () => ref.invalidate(exerciseTemplatesProvider),
      ),
      data: (allExercises) => foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LibraryLoadError(
          message: 'Could not load exercise folders: $error',
          onRetry: () => ref.invalidate(
            libraryFoldersProvider(LibraryItemType.exercise),
          ),
        ),
        data: (folders) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Exercise Library',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Drag to copy, or use Add. Sources stay unchanged.'),
            ),
            Expanded(
              child: LibraryOrganizer<ExerciseTemplate>(
                userId: userId,
                itemType: LibraryItemType.exercise,
                items: allExercises
                    .where((exercise) => exercise.currentVersion > 0)
                    .toList(),
                folders: folders,
                emptyMessage: 'No published exercises are available.',
                nameOf: (item) => item.name,
                tagsOf: (item) => item.tags,
                folderIdOf: (item) => item.folderId,
                clientAthleteIdOf: (_) => null,
                tileBuilder: (context, exercise, organizationButton) =>
                    _ExerciseLibraryTile(
                  exercise: exercise,
                  organizationButton: organizationButton,
                  onAdd: () => _addLibraryExercise(exercise),
                ),
                updateOrganization: (
                  item, {
                  required tags,
                  required folderId,
                  required clientAthleteId,
                }) =>
                    ref
                        .read(exerciseTemplateRepositoryProvider)
                        .updateOrganization(
                          id: item.id,
                          tags: tags,
                          folderId: folderId,
                          userId: userId,
                        ),
                createFolder: (name) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.exercise),
                    )
                    .create(name: name, userId: userId),
                renameFolder: (folder, name) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.exercise),
                    )
                    .rename(
                      folderId: folder.id,
                      name: name,
                      userId: userId,
                    ),
                deleteFolder: (folder) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.exercise),
                    )
                    .delete(folderId: folder.id, userId: userId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutCanvas(List<WorkoutBlock> blocks) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Workout Name'),
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _saveHeader(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<WorkoutType>(
          initialValue: _workoutType,
          decoration: const InputDecoration(labelText: 'Workout Type'),
          items: WorkoutType.values
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(type.name),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _workoutType = value);
              _saveHeader();
            }
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'Draft changes are private until Publish. Exercise versions remain '
          'pinned; adding never changes the library source.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Semantics(
              button: true,
              container: true,
              excludeSemantics: true,
              label: 'Save workout draft',
              child: OutlinedButton(
                onPressed: _isLoading ? null : _saveDraft,
                child: const Text('Save draft'),
              ),
            ),
            Semantics(
              button: true,
              container: true,
              excludeSemantics: true,
              label: 'Publish workout draft',
              child: FilledButton(
                onPressed: _isLoading ? null : _publish,
                child: const Text('Publish'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Workout canvas',
                style: Theme.of(context).textTheme.titleMedium),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<WorkoutBlockType>(
                  tooltip: 'Add typed block',
                  onSelected: _addTypedBlock,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: WorkoutBlockType.timedInterval,
                      child: Text('Timed interval'),
                    ),
                    PopupMenuItem(
                      value: WorkoutBlockType.circuit,
                      child: Text('Circuit'),
                    ),
                    PopupMenuItem(
                      value: WorkoutBlockType.climbingRoute,
                      child: Text('Climbing route'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Icon(Icons.view_agenda_outlined),
                        SizedBox(width: 4),
                        Text('Add block'),
                      ],
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addExercise,
                  icon: const Icon(Icons.add),
                  label: const Text('Add exercise'),
                ),
              ],
            ),
          ],
        ),
        _WorkoutInsertionTarget(
          label: 'Drop exercise at start',
          onAccept: (exercise) => _addLibraryExercise(exercise, index: 0),
          onReorder: (oldIndex) =>
              ref.read(workoutDraftProvider.notifier).reorder(oldIndex, 0),
        ),
        if (blocks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'Drag an exercise here or use Add exercise to begin.',
              ),
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < blocks.length; index++) ...[
                _WorkoutBlockCard(
                  key: ValueKey(blocks[index].blockId),
                  block: blocks[index],
                  index: index,
                  blockCount: blocks.length,
                ),
                _WorkoutInsertionTarget(
                  label: 'Drop exercise after ${index + 1}',
                  onAccept: (exercise) =>
                      _addLibraryExercise(exercise, index: index + 1),
                  onReorder: (oldIndex) => ref
                      .read(workoutDraftProvider.notifier)
                      .reorder(oldIndex, index + 1),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Future<void> _addTypedBlock(WorkoutBlockType type) async {
    final result = await showExercisePicker(context, ref);
    if (result == null) return;
    final repo = ref.read(workoutTemplateRepositoryProvider);
    try {
      ref.read(workoutDraftProvider.notifier).addTypedBlock(
            type: type,
            blockId: repo.generateWorkoutBlockId(),
            initialSlot: ExerciseSlot(
              slotId: repo.generateExerciseSlotId(),
              exerciseId: result.id,
              exerciseVersion: result.version,
              exerciseName: result.name,
              sortOrder: 0,
              mode: type == WorkoutBlockType.timedInterval
                  ? ExerciseMode.time
                  : ExerciseMode.reps,
              sets: type == WorkoutBlockType.timedInterval ? null : 3,
              reps: type == WorkoutBlockType.timedInterval ? null : '8-12',
              durationSeconds:
                  type == WorkoutBlockType.timedInterval ? 30 : null,
            ),
          );
    } on Object catch (error) {
      _showMessage('$error');
    }
  }

  Widget _buildCreationForm() {
    return Scaffold(
      appBar: AppBar(title: const Text('New Workout Template')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Workout Name'),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<WorkoutType>(
              value: _workoutType,
              decoration: const InputDecoration(labelText: 'Workout Type'),
              items: WorkoutType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.name),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _workoutType = value);
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isLoading ? null : _createAndEnter,
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create & Start Building'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card for a single exercise in the builder's reorderable list.
class _WorkoutBlockCard extends ConsumerWidget {
  const _WorkoutBlockCard({
    super.key,
    required this.block,
    required this.index,
    required this.blockCount,
  });

  final WorkoutBlock block;
  final int index;
  final int blockCount;

  String get _prescriptionSummary {
    if (block is TimedIntervalBlock) {
      final interval = block as TimedIntervalBlock;
      return '${interval.rounds} rounds · ${interval.workSeconds}s work · '
          '${interval.restSeconds}s rest';
    }
    if (block is CircuitBlock) {
      final circuit = block as CircuitBlock;
      return '${circuit.rounds} rounds · ${circuit.slots.length} exercises';
    }
    if (block is ClimbingRouteBlock) {
      final route = block as ClimbingRouteBlock;
      return '${route.grade} · ${route.color}';
    }
    final exercise = (block as StandardExerciseBlock).exercise;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStandard = block is StandardExerciseBlock;
    final exercise =
        isStandard ? (block as StandardExerciseBlock).exercise : null;
    final acceptsSlots = block is TimedIntervalBlock || block is CircuitBlock;
    final card = DragTarget<ExerciseTemplate>(
      onWillAccept: (_) => acceptsSlots,
      onAccept: (item) {
        ref.read(workoutDraftProvider.notifier).addLibraryExercise(
              exerciseId: item.id,
              exerciseVersion: item.currentVersion,
              exerciseName: item.name,
              targetBlockId: block.blockId,
            );
      },
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          border: Border.all(
            width: candidates.isNotEmpty || rejected.isNotEmpty ? 2 : 0,
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primary
                : rejected.isNotEmpty
                    ? Theme.of(context).colorScheme.error
                    : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Card(
            child: Column(
              children: [
                ListTile(
                  leading: Semantics(
                    label: 'Drag block ${index + 1}',
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Text(
                    exercise?.exerciseName ?? block.title ?? block.type.name,
                  ),
                  subtitle: Text(
                    acceptsSlots
                        ? '$_prescriptionSummary · Drop exercises into block'
                        : _prescriptionSummary,
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      Semantics(
                        button: true,
                        container: true,
                        excludeSemantics: true,
                        label: 'Move block up',
                        child: IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          tooltip: 'Move block up',
                          onPressed: index == 0
                              ? null
                              : () => ref
                                  .read(workoutDraftProvider.notifier)
                                  .moveUp(index),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward),
                        tooltip: 'Move block down',
                        onPressed: index == blockCount - 1
                            ? null
                            : () => ref
                                .read(workoutDraftProvider.notifier)
                                .moveDown(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_outlined),
                        tooltip: 'Duplicate block',
                        onPressed: () => ref
                            .read(workoutDraftProvider.notifier)
                            .duplicateAt(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit prescription',
                        onPressed: isStandard
                            ? () => _editPrescription(context, ref)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove block',
                        onPressed: () => ref
                            .read(workoutDraftProvider.notifier)
                            .removeAt(index),
                      ),
                    ],
                  ),
                ),
                if (!isStandard)
                  for (var slotIndex = 0;
                      slotIndex < block.slots.length;
                      slotIndex++)
                    ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.only(left: 56, right: 12),
                      title: Text(
                        block.slots[slotIndex].exerciseName ?? 'Exercise',
                      ),
                      subtitle: Text(
                        'Pinned v${block.slots[slotIndex].exerciseVersion}',
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Move slot up',
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            onPressed: slotIndex == 0
                                ? null
                                : () => ref
                                    .read(workoutDraftProvider.notifier)
                                    .reorderSlot(
                                      blockId: block.blockId,
                                      oldIndex: slotIndex,
                                      newIndex: slotIndex - 1,
                                    ),
                          ),
                          IconButton(
                            tooltip: 'Move slot down',
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            onPressed: slotIndex == block.slots.length - 1
                                ? null
                                : () => ref
                                    .read(workoutDraftProvider.notifier)
                                    .reorderSlot(
                                      blockId: block.blockId,
                                      oldIndex: slotIndex,
                                      newIndex: slotIndex + 2,
                                    ),
                          ),
                        ],
                      ),
                    ),
                if (rejected.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('This block accepts exactly one exercise.'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: 'Draggable block ${index + 1}',
      child: Draggable<_WorkoutBlockDragData>(
        data: _WorkoutBlockDragData(index),
        feedback: Material(
          elevation: 8,
          child: SizedBox(
            width: 420,
            child: ListTile(
              leading: const Icon(Icons.drag_handle),
              title: Text(
                exercise?.exerciseName ?? block.title ?? block.type.name,
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .45, child: card),
        child: card,
      ),
    );
  }

  void _editPrescription(BuildContext context, WidgetRef ref) {
    final exercise = (block as StandardExerciseBlock).exercise;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PrescriptionEditor(
        prescription: exercise,
        onSave: (updated) {
          ref
              .read(workoutDraftProvider.notifier)
              .updateExerciseAt(index, updated);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _ExerciseLibraryTile extends StatelessWidget {
  const _ExerciseLibraryTile({
    required this.exercise,
    required this.organizationButton,
    required this.onAdd,
  });

  final ExerciseTemplate exercise;
  final Widget organizationButton;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      title: Text(exercise.name),
      subtitle: Text('Published v${exercise.currentVersion}'),
      trailing: Wrap(
        children: [
          organizationButton,
          Semantics(
            button: true,
            container: true,
            excludeSemantics: true,
            label: 'Add ${exercise.name} to workout',
            child: IconButton(
              tooltip: 'Add ${exercise.name} to workout',
              icon: const Icon(Icons.add),
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: '${exercise.name}, draggable exercise, published version '
          '${exercise.currentVersion}',
      button: true,
      container: true,
      explicitChildNodes: true,
      child: Draggable<ExerciseTemplate>(
        data: exercise,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 280,
            child: ListTile(
              leading: const Icon(Icons.fitness_center),
              title: Text(exercise.name),
              subtitle: const Text('Copy into workout'),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .45, child: tile),
        child: tile,
      ),
    );
  }
}

class _WorkoutInsertionTarget extends StatelessWidget {
  const _WorkoutInsertionTarget({
    required this.label,
    required this.onAccept,
    this.onReorder,
  });

  final String label;
  final ValueChanged<ExerciseTemplate> onAccept;
  final ValueChanged<int>? onReorder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAccept: (data) =>
          data is ExerciseTemplate || data is _WorkoutBlockDragData,
      onAccept: (data) {
        if (data is ExerciseTemplate) {
          onAccept(data);
        } else if (data is _WorkoutBlockDragData) {
          onReorder?.call(data.index);
        }
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return Semantics(
          button: true,
          container: true,
          explicitChildNodes: true,
          focusable: true,
          label: label,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: active ? 34 : 24,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: active
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              border: Border(
                top: BorderSide(
                  width: active ? 3 : 1,
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).dividerColor,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Text(active ? 'Insert exercise here' : label),
          ),
        );
      },
    );
  }
}

class _WorkoutBlockDragData {
  const _WorkoutBlockDragData(this.index);

  final int index;
}

/// Bottom sheet for editing exercise prescription details.
class _PrescriptionEditor extends StatefulWidget {
  const _PrescriptionEditor({
    required this.prescription,
    required this.onSave,
  });

  final ExercisePrescription prescription;
  final ValueChanged<ExercisePrescription> onSave;

  @override
  State<_PrescriptionEditor> createState() => _PrescriptionEditorState();
}

class _PrescriptionEditorState extends State<_PrescriptionEditor> {
  late ExerciseMode _mode;
  late TextEditingController _setsController;
  late TextEditingController _repsController;
  late TextEditingController _durationController;
  late TextEditingController _weightController;
  late TextEditingController _restController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _mode = widget.prescription.mode;
    _setsController = TextEditingController(
      text: widget.prescription.sets?.toString() ?? '',
    );
    _repsController = TextEditingController(
      text: widget.prescription.reps ?? '',
    );
    _durationController = TextEditingController(
      text: widget.prescription.durationSeconds?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: widget.prescription.weight ?? '',
    );
    _restController = TextEditingController(
      text: widget.prescription.restSeconds?.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: widget.prescription.notes ?? '',
    );
  }

  @override
  void dispose() {
    _setsController.dispose();
    _repsController.dispose();
    _durationController.dispose();
    _weightController.dispose();
    _restController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(widget.prescription.copyWith(
      mode: _mode,
      sets: int.tryParse(_setsController.text),
      reps: _repsController.text.isEmpty ? null : _repsController.text,
      durationSeconds: int.tryParse(_durationController.text),
      weight: _weightController.text.isEmpty ? null : _weightController.text,
      restSeconds: int.tryParse(_restController.text),
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Edit Prescription',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ExerciseMode>(
            value: _mode,
            decoration: const InputDecoration(labelText: 'Mode'),
            items: ExerciseMode.values.map((mode) {
              return DropdownMenuItem(value: mode, child: Text(mode.name));
            }).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _mode = v);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _setsController,
                  decoration: const InputDecoration(labelText: 'Sets'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _repsController,
                  decoration:
                      const InputDecoration(labelText: 'Reps (e.g. 8-12)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _durationController,
                  decoration:
                      const InputDecoration(labelText: 'Duration (sec)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _restController,
                  decoration: const InputDecoration(labelText: 'Rest (sec)'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weightController,
            decoration: const InputDecoration(
              labelText: 'Weight (e.g. 135 lb or 70%)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
