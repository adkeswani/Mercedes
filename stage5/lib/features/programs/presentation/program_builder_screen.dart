import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_organizer.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/programs/presentation/enrollment_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/programs/presentation/workout_picker.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

/// Sentinel value for the "create a new folder" option in the folder dropdown.
const _kNewFolderSentinel = '__new_folder__';

/// Builder screen for creating/editing a program.
///
/// Collects header info (name, description, type) and manages a local draft
/// of workout references. Changes are only persisted on Publish.
class ProgramBuilderScreen extends ConsumerStatefulWidget {
  const ProgramBuilderScreen({super.key, this.programId, this.copyFromId});

  final String? programId;

  /// When set, pre-populates the draft with workouts from this program.
  final String? copyFromId;

  bool get isEditing => programId != null;

  @override
  ConsumerState<ProgramBuilderScreen> createState() =>
      _ProgramBuilderScreenState();
}

class _ProgramBuilderScreenState extends ConsumerState<ProgramBuilderScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  ProgramType _programType = ProgramType.assignable;
  bool _isLoading = false;
  bool _didLoad = false;
  String? _ownerId;
  String? _folderId;
  String? _clientAthleteId;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(programDraftProvider.notifier).clear();
    });
  }

  @override
  void didUpdateWidget(covariant ProgramBuilderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.programId == widget.programId &&
        oldWidget.copyFromId == widget.copyFromId) {
      return;
    }
    _didLoad = true;
    _nameController.clear();
    _descriptionController.clear();
    _programType = ProgramType.assignable;
    _ownerId = null;
    _folderId = null;
    _clientAthleteId = null;
    final programId = widget.programId;
    Future.microtask(() {
      if (!mounted || widget.programId != programId) return;
      ref.read(programDraftProvider.notifier).clear();
      _didLoad = false;
      _loadExisting();
    });
  }

  Future<void> _loadExisting() async {
    if (_didLoad || !widget.isEditing) return;
    _didLoad = true;

    final repo = ref.read(programRepositoryProvider);
    final programId = widget.programId!;
    final program = await repo.getById(programId);
    if (program == null || !mounted || widget.programId != programId) return;

    _nameController.text = program.name;
    _descriptionController.text = program.description ?? '';
    setState(() {
      _programType = program.type;
      _ownerId = program.ownerId;
      _folderId = program.folderId;
      _clientAthleteId = program.clientAthleteId;
    });

    // If copying from another program, load its workouts
    final source = resolveLibraryEditorSource(
      targetTemplateId: programId,
      targetVersion: program.currentVersion,
      routeSourceTemplateId: widget.copyFromId,
      provenance: program.provenance,
    );
    final sourceVersion = source.version ??
        (await repo.getById(source.templateId))?.currentVersion ??
        0;
    final savedDraft = await repo.getSavedDraft(programId);
    if (savedDraft != null && mounted && widget.programId == programId) {
      ref
          .read(programDraftProvider.notifier)
          .load(savedDraft.entries, phases: savedDraft.phases);
    } else if (sourceVersion > 0) {
      final version = await repo.getVersion(source.templateId, sourceVersion);
      if (version != null && mounted && widget.programId == programId) {
        ref
            .read(programDraftProvider.notifier)
            .load(version.entries, phases: version.phases);
      }
    }
  }

  Future<void> _createAndEnter() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }

    // Check for duplicate name
    final existing = ref.read(programsProvider).valueOrNull ?? [];
    if (existing.any((p) => p.name == name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A program with that name already exists'),
          ),
        );
      }
      return;
    }

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(programRepositoryProvider);
      final id = await repo.create(
        name: name,
        type: _programType,
        userId: uid,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );
      if (mounted) {
        context.pushReplacement('/programs/$id');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create: $e')));
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

    final repo = ref.read(programRepositoryProvider);
    await repo.update(
      id: widget.programId!,
      name: _nameController.text.trim(),
      userId: uid,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );
  }

  Future<void> _publish() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final programId = widget.programId!;
    final draft = ref.read(programDraftProvider);
    final draftRevision = ref.read(programDraftProvider.notifier).revision;
    if (draft.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one workout first')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _saveHeader();

      final repo = ref.read(programRepositoryProvider);
      final version = await repo.publishVersion(
        programId: programId,
        entries: draft.entries,
        phases: draft.phases,
        userId: uid,
      );

      if (mounted) {
        if (widget.programId == programId &&
            ref.read(programDraftProvider.notifier).revision == draftRevision) {
          ref.read(programDraftProvider.notifier).markSaved();
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Published version $version')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to publish: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDraft() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    final programId = widget.programId!;
    final draft = ref.read(programDraftProvider);
    final draftRevision = ref.read(programDraftProvider.notifier).revision;
    if (draft.entries.isEmpty) {
      _showMessage('Add at least one workout first');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _saveHeader();
      await ref.read(programRepositoryProvider).saveDraft(
            programId: programId,
            entries: draft.entries,
            phases: draft.phases,
            userId: uid,
          );
      if (mounted &&
          widget.programId == programId &&
          ref.read(programDraftProvider.notifier).revision == draftRevision) {
        ref.read(programDraftProvider.notifier).markSaved();
      }
      if (mounted) _showMessage('Draft saved. Publishing is still required.');
    } catch (error) {
      if (mounted) _showMessage('Failed to save draft: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!ref.read(programDraftProvider).isDirty) return true;
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

  Future<void> _discardDraft() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null || !await _confirmDiscard()) return;
    await ref.read(programRepositoryProvider).discardDraft(
          programId: widget.programId!,
          userId: uid,
        );
    final program =
        await ref.read(programRepositoryProvider).getById(widget.programId!);
    final version = program != null && program.currentVersion > 0
        ? await ref
            .read(programRepositoryProvider)
            .getVersion(program.id, program.currentVersion)
        : null;
    ref.read(programDraftProvider.notifier).load(
          version?.entries ?? const [],
          phases: version?.phases ?? const [],
        );
    if (mounted) _showMessage('Draft changes discarded');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addWorkoutTemplate(
    WorkoutTemplate workout, {
    String? phaseId,
    int? index,
  }) async {
    final offset = await _pickDayOffset();
    if (offset == null) return;
    try {
      ref.read(programDraftProvider.notifier).addWorkout(
            ProgramScheduleEntry(
              workoutTemplateId: workout.id,
              workoutTemplateVersion: workout.currentVersion,
              dayOffset: offset,
              sortOrder: 0,
              workoutName: workout.name,
              phaseId: phaseId,
            ),
            index: index,
            phaseId: phaseId,
          );
    } on Object catch (error) {
      _showMessage('$error');
    }
  }

  Future<void> _addPhase() async {
    final name = await _promptText(title: 'Add phase', label: 'Phase name');
    if (name == null || name.trim().isEmpty) return;
    ref.read(programDraftProvider.notifier).addPhase(name);
  }

  Future<void> _renamePhase(ProgramPhase phase) async {
    final name = await _promptText(
      title: 'Rename phase',
      label: 'Phase name',
      initialValue: phase.name,
    );
    if (name == null || name.trim().isEmpty) return;
    ref.read(programDraftProvider.notifier).renamePhase(phase.phaseId, name);
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  void _addWorkout() async {
    final result = await showWorkoutPicker(
      context,
      ref,
      clientAthleteId: _clientAthleteId,
    );
    if (result == null || !mounted) return;

    final offset = await _pickDayOffset();
    if (offset == null) return;

    final workouts = ref.read(programDraftProvider).entries;
    ref.read(programDraftProvider.notifier).addWorkout(
          ProgramScheduleEntry(
            workoutTemplateId: result.id,
            workoutTemplateVersion: result.currentVersion,
            dayOffset: offset,
            sortOrder: workouts.length,
            workoutName: result.name,
          ),
        );
  }

  /// Picks a workout then generates entries across recurring day offsets.
  void _generateRecurring() async {
    final result = await showWorkoutPicker(
      context,
      ref,
      clientAthleteId: _clientAthleteId,
    );
    if (result == null || !mounted) return;

    final offsets = await showDialog<List<int>>(
      context: context,
      builder: (_) => const _RecurrenceGeneratorDialog(),
    );
    if (offsets == null || offsets.isEmpty) return;

    final entries = [
      for (final offset in offsets)
        ProgramScheduleEntry(
          workoutTemplateId: result.id,
          workoutTemplateVersion: result.currentVersion,
          dayOffset: offset,
          sortOrder: 0,
          workoutName: result.name,
        ),
    ];
    ref.read(programDraftProvider.notifier).addAll(entries);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${entries.length} occurrences')),
      );
    }
  }

  /// Shows a day picker (Day 1 = program start date), returning the chosen
  /// zero-based day offset (or null). Day N maps to offset N - 1.
  Future<int?> _pickDayOffset({int initial = 0}) {
    var offset = initial;
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Choose day'),
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Day '),
                  DropdownButton<int>(
                    value: offset,
                    items: [
                      for (var d = 0; d < 182; d++)
                        DropdownMenuItem(value: d, child: Text('${d + 1}')),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => offset = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(offset),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Compact relative-week calendar overview of the draft schedule, showing
  /// the workout name(s) on each day so owners can see what they've assigned.
  Widget _buildScheduleCalendar(
    BuildContext context,
    List<ProgramScheduleEntry> entries,
  ) {
    // Resolve template names for entries lacking a denormalized workoutName.
    final templates =
        ref.watch(workoutTemplatesProvider).valueOrNull ?? const [];
    final nameById = {for (final t in templates) t.id: t.name};
    String nameFor(ProgramScheduleEntry e) =>
        e.workoutName ?? nameById[e.workoutTemplateId] ?? 'Workout';

    final byOffset = <int, List<String>>{};
    var maxOffset = 0;
    for (final e in entries) {
      byOffset.putIfAbsent(e.dayOffset, () => []).add(nameFor(e));
      if (e.dayOffset > maxOffset) maxOffset = e.dayOffset;
    }
    final weeks = maxOffset ~/ 7 + 1;
    final theme = Theme.of(context);

    final weekRows = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final dayCells = <Widget>[
        for (var d = 0; d < 7; d++)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(2),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minHeight: 52),
              decoration: BoxDecoration(
                color: (byOffset[w * 7 + d] ?? const []).isEmpty
                    ? null
                    : theme.colorScheme.primaryContainer,
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Day ${w * 7 + d + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  for (final n in byOffset[w * 7 + d] ?? const [])
                    Text(
                      n,
                      style: theme.textTheme.labelSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
      ];
      weekRows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Days ${w * 7 + 1}-${w * 7 + 7}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(child: Row(children: dayCells)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: weekRows,
        ),
      ),
    );
  }

  Widget _buildFolderSelector() {
    final foldersAsync = ref.watch(programFoldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];
    final value = folders.any((f) => f.id == _folderId) ? _folderId : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('folder-picker-$value'),
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Folder'),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        for (final f in folders)
          DropdownMenuItem(value: f.id, child: Text(f.name)),
        const DropdownMenuItem(
          value: _kNewFolderSentinel,
          child: Text('+ New folder…'),
        ),
      ],
      onChanged: _onFolderSelected,
    );
  }

  Future<void> _onFolderSelected(String? value) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    String? targetFolderId;
    if (value == _kNewFolderSentinel) {
      final name = await _promptFolderName();
      if (name == null || name.trim().isEmpty) return;
      targetFolderId = await ref
          .read(programFolderRepositoryProvider)
          .create(name: name.trim(), userId: uid);
    } else {
      targetFolderId = value;
    }

    await ref.read(programRepositoryProvider).setFolder(
          id: widget.programId!,
          folderId: targetFolderId,
          userId: uid,
        );
    if (mounted) setState(() => _folderId = targetFolderId);
  }

  Future<String?> _promptFolderName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleProgramType() async {
    if (!widget.isEditing) return;
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final newType = _programType == ProgramType.assignable
        ? ProgramType.personal
        : ProgramType.assignable;

    // Block assignable → personal if athletes are enrolled
    if (newType == ProgramType.personal) {
      final enrollmentRepo = ref.read(enrollmentRepositoryProvider);
      final enrollments = await enrollmentRepo
          .watchEnrollments(widget.programId!, ownerId: uid)
          .first;
      if (enrollments.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Remove all enrolled athletes before switching to personal',
            ),
          ),
        );
        return;
      }
    }

    final repo = ref.read(programRepositoryProvider);
    await repo.updateType(id: widget.programId!, type: newType, userId: uid);
    if (mounted) setState(() => _programType = newType);
  }

  Future<void> _deleteProgram() async {
    // Block deletion if athletes are enrolled
    if (_programType == ProgramType.assignable) {
      final uid = ref.read(authStateProvider).value?.uid;
      if (uid == null) return;
      final enrollmentRepo = ref.read(enrollmentRepositoryProvider);
      final enrollments = await enrollmentRepo
          .watchEnrollments(widget.programId!, ownerId: uid)
          .first;
      if (enrollments.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Remove all enrolled athletes before deleting this program',
            ),
          ),
        );
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete program?'),
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

    await ref
        .read(programRepositoryProvider)
        .softDelete(widget.programId!, uid);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing && !_didLoad) {
      _loadExisting();
    }

    final draft = ref.watch(programDraftProvider);

    if (!widget.isEditing) {
      return _buildCreationForm();
    }

    final uid = ref.watch(authStateProvider).value?.uid;
    final isOwner = _ownerId != null && _ownerId == uid;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(isOwner ? 'Program Builder' : 'Program Details'),
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo last canvas change',
              onPressed: draft.canUndo
                  ? ref.read(programDraftProvider.notifier).undo
                  : null,
            ),
          if (isOwner)
            TextButton(
              onPressed: _isLoading ? null : _saveDraft,
              child: const Text('Save draft'),
            ),
          if (isOwner)
            TextButton(
              onPressed: _isLoading ? null : _discardDraft,
              child: const Text('Discard'),
            ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete program',
              onPressed: _isLoading ? null : _deleteProgram,
            ),
          if (isOwner)
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
          final canvas = _buildProgramCanvas(draft, isOwner);
          if (!isOwner || constraints.maxWidth < 900) return canvas;
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
                  child: _buildWorkoutLibrary(),
                ),
              ),
              Expanded(child: canvas),
            ],
          );
        },
      ),
    );
    return WillPopScope(
      onWillPop: isOwner ? _confirmDiscard : () async => true,
      child: scaffold,
    );
  }

  Widget _buildWorkoutLibrary() {
    final workoutsAsync = ref.watch(workoutTemplatesProvider);
    final foldersAsync = ref.watch(
      libraryFoldersProvider(LibraryItemType.workout),
    );
    final clientNames =
        ref.watch(activeTrainerClientNamesProvider).valueOrNull ?? const {};
    final userId = ref.watch(authStateProvider).valueOrNull?.uid;
    if (userId == null) {
      return const Center(child: Text('Sign in to view workouts.'));
    }
    return workoutsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => LibraryLoadError(
        message: 'Could not load workouts: $error',
        onRetry: () => ref.invalidate(workoutTemplatesProvider),
      ),
      data: (allWorkouts) => foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LibraryLoadError(
          message: 'Could not load workout folders: $error',
          onRetry: () =>
              ref.invalidate(libraryFoldersProvider(LibraryItemType.workout)),
        ),
        data: (folders) {
          final workouts = allWorkouts.where((workout) {
            if (!workout.hasPublishedVersion) return false;
            return workout.clientAthleteId == null ||
                workout.clientAthleteId == _clientAthleteId;
          }).toList();
          final scopeLabel = _clientAthleteId == null
              ? 'Shared program: shared workouts only'
              : 'Client program: ${clientNames[_clientAthleteId] ?? _clientAthleteId}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Workout Library',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  '$scopeLabel. Dragging copies and pins the current version.',
                ),
              ),
              Expanded(
                child: LibraryOrganizer<WorkoutTemplate>(
                  userId: userId,
                  itemType: LibraryItemType.workout,
                  items: workouts,
                  folders: folders,
                  emptyMessage:
                      'No published workouts match this program scope.',
                  nameOf: (item) => item.name,
                  tagsOf: (item) => item.tags,
                  folderIdOf: (item) => item.folderId,
                  clientAthleteIdOf: (item) => item.clientAthleteId,
                  activeClientNames: clientNames,
                  supportsClientScope: true,
                  tileBuilder: (context, workout, organizationButton) =>
                      _WorkoutLibraryTile(
                    workout: workout,
                    organizationButton: organizationButton,
                    onAdd: () => _addWorkoutTemplate(workout),
                  ),
                  updateOrganization: (
                    item, {
                    required tags,
                    required folderId,
                    required clientAthleteId,
                  }) =>
                      ref
                          .read(workoutTemplateRepositoryProvider)
                          .updateOrganization(
                            id: item.id,
                            tags: tags,
                            folderId: folderId,
                            clientAthleteId: clientAthleteId,
                            updateClientScope: true,
                            userId: userId,
                          ),
                  createFolder: (name) => ref
                      .read(
                        libraryFolderRepositoryProvider(
                          LibraryItemType.workout,
                        ),
                      )
                      .create(name: name, userId: userId),
                  renameFolder: (folder, name) => ref
                      .read(
                        libraryFolderRepositoryProvider(
                          LibraryItemType.workout,
                        ),
                      )
                      .rename(folderId: folder.id, name: name, userId: userId),
                  deleteFolder: (folder) => ref
                      .read(
                        libraryFolderRepositoryProvider(
                          LibraryItemType.workout,
                        ),
                      )
                      .delete(folderId: folder.id, userId: userId),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgramCanvas(ProgramDraftState draft, bool isOwner) {
    final phaseNames = {
      for (final phase in draft.phases) phase.phaseId: phase.name,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Program Name'),
          textCapitalization: TextCapitalization.words,
          onChanged: isOwner ? (_) => _saveHeader() : null,
          readOnly: !isOwner,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          maxLines: 3,
          onChanged: isOwner ? (_) => _saveHeader() : null,
          readOnly: !isOwner,
        ),
        if (isOwner) ...[
          const SizedBox(height: 16),
          SwitchListTile(
            title: Text(
              _programType == ProgramType.assignable
                  ? 'Assignable'
                  : 'Personal',
            ),
            subtitle: Text(
              _programType == ProgramType.assignable
                  ? 'Athletes can be enrolled'
                  : 'Self-use only',
            ),
            value: _programType == ProgramType.assignable,
            onChanged: (_) => _toggleProgramType(),
          ),
          const SizedBox(height: 8),
          _buildFolderSelector(),
        ],
        const SizedBox(height: 12),
        Text(
          _clientAthleteId == null
              ? 'Scope: Shared. Adding a workout creates an independent '
                  'pinned reference; subscriptions and source templates are '
                  'not changed.'
              : 'Scope: Client ${_clientAthleteId!}. Only shared or matching '
                  'client workouts can be published.',
        ),
        if (isOwner) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Semantics(
                button: true,
                container: true,
                excludeSemantics: true,
                label: 'Save program draft',
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _saveDraft,
                  child: const Text('Save draft'),
                ),
              ),
              Semantics(
                button: true,
                container: true,
                excludeSemantics: true,
                label: 'Publish program draft',
                child: FilledButton(
                  onPressed: _isLoading ? null : _publish,
                  child: const Text('Publish'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Phases', style: Theme.of(context).textTheme.titleMedium),
            if (isOwner)
              TextButton.icon(
                onPressed: _addPhase,
                icon: const Icon(Icons.add),
                label: const Text('Add phase'),
              ),
          ],
        ),
        if (draft.phases.isEmpty)
          const Text(
            'No phases. Phases are optional organizational sections and do '
            'not change progression logic.',
          )
        else
          Column(
            children: [
              for (var index = 0; index < draft.phases.length; index++)
                _ProgramPhaseCard(
                  key: ValueKey(draft.phases[index].phaseId),
                  phase: draft.phases[index],
                  index: index,
                  phaseCount: draft.phases.length,
                  onRename: () => _renamePhase(draft.phases[index]),
                  onDropWorkout: (workout) => _addWorkoutTemplate(
                    workout,
                    phaseId: draft.phases[index].phaseId,
                  ),
                  onReorder: (oldIndex) => ref
                      .read(programDraftProvider.notifier)
                      .reorderPhase(oldIndex, index + 1),
                ),
            ],
          ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Chronological draft',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (isOwner)
              Wrap(
                children: [
                  TextButton.icon(
                    onPressed: _generateRecurring,
                    icon: const Icon(Icons.repeat, size: 18),
                    label: const Text('Recurring'),
                  ),
                  TextButton.icon(
                    onPressed: _addWorkout,
                    icon: const Icon(Icons.add),
                    label: const Text('Add workout'),
                  ),
                ],
              ),
          ],
        ),
        if (draft.entries.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildScheduleCalendar(context, draft.entries),
        ],
        _ProgramInsertionTarget(
          label: 'Drop workout at start',
          onAccept: (workout) => _addWorkoutTemplate(workout, index: 0),
          onReorder: (oldIndex) =>
              ref.read(programDraftProvider.notifier).reorder(oldIndex, 0),
        ),
        if (draft.entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('Drag a workout here or use Add workout to begin.'),
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < draft.entries.length; index++)
                Column(
                  key: ValueKey(draft.entries[index].resolvedEntryId),
                  children: [
                    _WorkoutCard(
                      workout: draft.entries[index],
                      isOwner: isOwner,
                      index: index,
                      entryCount: draft.entries.length,
                      phaseName: draft.entries[index].phaseId == null
                          ? null
                          : phaseNames[draft.entries[index].phaseId],
                      onEditDay: isOwner
                          ? () async {
                              final offset = await _pickDayOffset(
                                initial: draft.entries[index].dayOffset,
                              );
                              if (offset != null) {
                                ref
                                    .read(programDraftProvider.notifier)
                                    .setDayOffset(index, offset);
                              }
                            }
                          : null,
                      onRemove: isOwner
                          ? () => ref
                              .read(programDraftProvider.notifier)
                              .removeAt(index)
                          : null,
                    ),
                    _ProgramInsertionTarget(
                      label: 'Drop workout after ${index + 1}',
                      onAccept: (workout) =>
                          _addWorkoutTemplate(workout, index: index + 1),
                      onReorder: (oldIndex) => ref
                          .read(programDraftProvider.notifier)
                          .reorder(oldIndex, index + 1),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCreationForm() {
    return Scaffold(
      appBar: AppBar(title: const Text('New Program')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Program Name'),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ProgramType>(
              initialValue: _programType,
              decoration: const InputDecoration(labelText: 'Program Type'),
              items: ProgramType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(
                    type == ProgramType.assignable
                        ? 'Assignable (can enroll athletes)'
                        : 'Personal (self-use only)',
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _programType = value);
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

/// Card for a single workout in the builder's schedule.
class _WorkoutCard extends ConsumerWidget {
  const _WorkoutCard({
    required this.workout,
    required this.isOwner,
    this.index,
    this.entryCount,
    this.phaseName,
    this.onEditDay,
    this.onRemove,
  });

  final ProgramScheduleEntry workout;
  final bool isOwner;
  final int? index;
  final int? entryCount;
  final String? phaseName;
  final VoidCallback? onEditDay;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer denormalized name from the published version snapshot
    if (workout.workoutName != null) {
      return _buildCard(context, ref, workout.workoutName!);
    }

    // For owners, fall back to live stream of own templates
    if (isOwner) {
      final workoutsAsync = ref.watch(workoutTemplatesProvider);
      final name = workoutsAsync.whenOrNull(
            data: (templates) {
              final match = templates
                  .where((t) => t.id == workout.workoutTemplateId)
                  .toList();
              return match.isNotEmpty ? match.first.name : null;
            },
          ) ??
          'Loading...';
      return _buildCard(context, ref, name);
    }

    // For non-owners, do a direct lookup by ID
    final workoutRepo = ref.watch(workoutTemplateRepositoryProvider);
    return FutureBuilder(
      future: workoutRepo.getById(workout.workoutTemplateId),
      builder: (context, snapshot) {
        final name = snapshot.data?.name ?? 'Loading...';
        return _buildCard(context, ref, name);
      },
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref, String name) {
    final card = Semantics(
      container: true,
      explicitChildNodes: true,
      child: Card(
        child: ListTile(
          leading: index == null
              ? null
              : Semantics(
                  label: 'Drag workout ${index! + 1}',
                  child: const Icon(Icons.drag_handle),
                ),
          title: Text(name),
          subtitle: Text(
            'Day ${workout.dayOffset + 1} · pinned '
            'v${workout.workoutTemplateVersion}'
            '${phaseName == null ? '' : ' · $phaseName'}',
          ),
          trailing: isOwner
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (index != null)
                      Semantics(
                        button: true,
                        container: true,
                        excludeSemantics: true,
                        label: 'Move workout up',
                        child: IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 20),
                          tooltip: 'Move workout up',
                          onPressed: index == 0
                              ? null
                              : () => ref
                                  .read(programDraftProvider.notifier)
                                  .moveUp(index!),
                        ),
                      ),
                    if (index != null)
                      IconButton(
                        icon: const Icon(Icons.arrow_downward, size: 20),
                        tooltip: 'Move workout down',
                        onPressed: index == entryCount! - 1
                            ? null
                            : () => ref
                                .read(programDraftProvider.notifier)
                                .moveDown(index!),
                      ),
                    if (index != null)
                      IconButton(
                        icon: const Icon(Icons.copy_outlined, size: 20),
                        tooltip: 'Duplicate workout entry',
                        onPressed: () => ref
                            .read(programDraftProvider.notifier)
                            .duplicateAt(index!),
                      ),
                    IconButton(
                      icon: const Icon(Icons.event, size: 20),
                      tooltip: 'Change day',
                      onPressed: onEditDay,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: onRemove,
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
    if (index == null) return card;
    return Semantics(
      label: 'Draggable workout ${index! + 1}',
      child: Draggable<_ProgramEntryDragData>(
        data: _ProgramEntryDragData(index!),
        feedback: Material(
          elevation: 8,
          child: SizedBox(
            width: 420,
            child: ListTile(
              leading: const Icon(Icons.drag_handle),
              title: Text(name),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .45, child: card),
        child: card,
      ),
    );
  }
}

class _WorkoutLibraryTile extends StatelessWidget {
  const _WorkoutLibraryTile({
    required this.workout,
    required this.organizationButton,
    required this.onAdd,
  });

  final WorkoutTemplate workout;
  final Widget organizationButton;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      title: Text(workout.name),
      subtitle: Text('Published v${workout.currentVersion}'),
      trailing: Wrap(
        children: [
          organizationButton,
          Semantics(
            button: true,
            container: true,
            excludeSemantics: true,
            label: 'Add ${workout.name} to program',
            child: IconButton(
              tooltip: 'Add ${workout.name} to program',
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: '${workout.name}, draggable workout, published version '
          '${workout.currentVersion}',
      button: true,
      container: true,
      explicitChildNodes: true,
      child: Draggable<WorkoutTemplate>(
        data: workout,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 280,
            child: ListTile(
              leading: const Icon(Icons.fitness_center),
              title: Text(workout.name),
              subtitle: Text('Copy pinned v${workout.currentVersion}'),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .45, child: tile),
        child: tile,
      ),
    );
  }
}

class _ProgramInsertionTarget extends StatelessWidget {
  const _ProgramInsertionTarget({
    required this.label,
    required this.onAccept,
    this.onReorder,
  });

  final String label;
  final ValueChanged<WorkoutTemplate> onAccept;
  final ValueChanged<int>? onReorder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAccept: (data) =>
          data is WorkoutTemplate || data is _ProgramEntryDragData,
      onAccept: (data) {
        if (data is WorkoutTemplate) {
          onAccept(data);
        } else if (data is _ProgramEntryDragData) {
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
            child: Text(active ? 'Insert workout here' : label),
          ),
        );
      },
    );
  }
}

class _ProgramPhaseCard extends ConsumerWidget {
  const _ProgramPhaseCard({
    required super.key,
    required this.phase,
    required this.index,
    required this.phaseCount,
    required this.onRename,
    required this.onDropWorkout,
    required this.onReorder,
  });

  final ProgramPhase phase;
  final int index;
  final int phaseCount;
  final VoidCallback onRename;
  final ValueChanged<WorkoutTemplate> onDropWorkout;
  final ValueChanged<int> onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = DragTarget<Object>(
      onWillAccept: (data) =>
          data is WorkoutTemplate || data is _ProgramPhaseDragData,
      onAccept: (data) {
        if (data is WorkoutTemplate) {
          onDropWorkout(data);
        } else if (data is _ProgramPhaseDragData) {
          onReorder(data.index);
        }
      },
      builder: (context, candidates, rejected) => Semantics(
        container: true,
        explicitChildNodes: true,
        child: Card(
          color: candidates.isNotEmpty
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: Semantics(
              label: 'Drag phase ${index + 1}',
              child: const Icon(Icons.drag_handle),
            ),
            title: Text(phase.name),
            subtitle: const Text('Organizational section'),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Move phase up',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: index == 0
                      ? null
                      : () => ref
                          .read(programDraftProvider.notifier)
                          .reorderPhase(index, index - 1),
                ),
                Semantics(
                  button: true,
                  container: true,
                  excludeSemantics: true,
                  label: 'Move phase down',
                  child: IconButton(
                    tooltip: 'Move phase down',
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: index == phaseCount - 1
                        ? null
                        : () => ref
                            .read(programDraftProvider.notifier)
                            .reorderPhase(index, index + 2),
                  ),
                ),
                IconButton(
                  tooltip: 'Rename phase',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onRename,
                ),
                IconButton(
                  tooltip: 'Remove phase',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref
                      .read(programDraftProvider.notifier)
                      .removePhase(phase.phaseId),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: 'Draggable phase ${index + 1}',
      child: Draggable<_ProgramPhaseDragData>(
        data: _ProgramPhaseDragData(index),
        feedback: Material(
          elevation: 8,
          child: SizedBox(
            width: 420,
            child: ListTile(
              leading: const Icon(Icons.drag_handle),
              title: Text(phase.name),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .45, child: card),
        child: card,
      ),
    );
  }
}

class _ProgramEntryDragData {
  const _ProgramEntryDragData(this.index);

  final int index;
}

class _ProgramPhaseDragData {
  const _ProgramPhaseDragData(this.index);

  final int index;
}

/// Human-readable label for a program day offset (0-based). Day 1 is the
/// program start date, so offset N renders as "Day N+1".
String dayLabel(int offset) => 'Day ${offset + 1}';

/// Dialog for generating a recurring set of day offsets for a workout.
class _RecurrenceGeneratorDialog extends StatefulWidget {
  const _RecurrenceGeneratorDialog();

  @override
  State<_RecurrenceGeneratorDialog> createState() =>
      _RecurrenceGeneratorDialogState();
}

class _RecurrenceGeneratorDialogState
    extends State<_RecurrenceGeneratorDialog> {
  int _startWeek = 0;
  final Set<int> _weekdays = {0};
  int _weeks = 4;
  bool _custom = false;
  int _intervalDays = 2;

  List<int> _generate() {
    final startDayOffset = _startWeek * 7;
    final horizonDays = _weeks * 7 - 1;
    if (_custom) {
      return expandRecurrenceOffsets(
        startDayOffset: startDayOffset,
        pattern: RecurrencePattern.custom,
        horizonDays: horizonDays,
        intervalDays: _intervalDays,
      );
    }
    if (_weekdays.isEmpty) return const [];
    return expandRecurrenceOffsets(
      startDayOffset: startDayOffset,
      pattern: RecurrencePattern.weekly,
      horizonDays: horizonDays,
      daysOfWeek: _weekdays.map((d) => d + 1).toList()..sort(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate recurring'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Start: '),
                DropdownButton<int>(
                  value: _startWeek,
                  items: [
                    for (var w = 0; w < 26; w++)
                      DropdownMenuItem(value: w, child: Text('Week ${w + 1}')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _startWeek = v);
                  },
                ),
                const SizedBox(width: 12),
                const Text('for '),
                DropdownButton<int>(
                  value: _weeks,
                  items: [
                    for (var w = 1; w <= 26; w++)
                      DropdownMenuItem(value: w, child: Text('$w wk')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _weeks = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Every N days'),
              value: _custom,
              onChanged: (v) => setState(() => _custom = v),
            ),
            if (_custom)
              Row(
                children: [
                  const Text('Every '),
                  DropdownButton<int>(
                    value: _intervalDays,
                    items: [
                      for (var d = 1; d <= 14; d++)
                        DropdownMenuItem(value: d, child: Text('$d')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _intervalDays = v);
                    },
                  ),
                  const Text(' days'),
                ],
              )
            else
              Wrap(
                spacing: 4,
                children: [
                  for (var d = 0; d < 7; d++)
                    FilterChip(
                      label: Text('D${d + 1}'),
                      selected: _weekdays.contains(d),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _weekdays.add(d);
                        } else {
                          _weekdays.remove(d);
                        }
                      }),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_generate()),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}
