import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/auth/presentation/app_entry_providers.dart';
import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/programs/domain/program.dart';
import 'package:stage4/features/programs/presentation/enrollment_providers.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';
import 'package:stage4/features/programs/presentation/workout_picker.dart';
import 'package:stage4/features/workouts/domain/workout_instance.dart';
import 'package:stage4/features/workouts/presentation/workout_providers.dart';

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

  Future<void> _loadExisting() async {
    if (_didLoad || !widget.isEditing) return;
    _didLoad = true;

    final repo = ref.read(programRepositoryProvider);
    final program = await repo.getById(widget.programId!);
    if (program == null || !mounted) return;

    _nameController.text = program.name;
    _descriptionController.text = program.description ?? '';
    setState(() {
      _programType = program.type;
      _ownerId = program.ownerId;
      _folderId = program.folderId;
    });

    // If copying from another program, load its workouts
    final sourceId = widget.copyFromId ?? widget.programId!;
    final sourceProgram = widget.copyFromId != null
        ? await repo.getById(widget.copyFromId!)
        : program;

    if (sourceProgram != null && sourceProgram.currentVersion > 0) {
      final version = await repo.getVersion(
        sourceId,
        sourceProgram.currentVersion,
      );
      if (version != null && mounted) {
        ref.read(programDraftProvider.notifier).load(version.entries);
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

    final workouts = ref.read(programDraftProvider);
    if (workouts.isEmpty) {
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
        programId: widget.programId!,
        entries: workouts,
        userId: uid,
      );

      if (mounted) {
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

  void _addWorkout() async {
    final result = await showWorkoutPicker(context, ref);
    if (result == null || !mounted) return;

    final offset = await _pickDayOffset();
    if (offset == null) return;

    final workouts = ref.read(programDraftProvider);
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
    final result = await showWorkoutPicker(context, ref);
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

  /// Shows a week/weekday picker, returning the chosen day offset (or null).
  Future<int?> _pickDayOffset({int initial = 0}) {
    var week = initial ~/ 7;
    var weekday = initial % 7;
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
                  DropdownButton<int>(
                    value: week,
                    items: [
                      for (var w = 0; w < 26; w++)
                        DropdownMenuItem(value: w, child: Text('Week ${w + 1}')),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => week = v);
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: weekday,
                    items: [
                      for (var d = 0; d < 7; d++)
                        DropdownMenuItem(
                          value: d,
                          child: Text(_weekdayName(d)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => weekday = v);
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
                  onPressed: () => Navigator.of(ctx).pop(week * 7 + weekday),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Builds day-grouped schedule sections from the draft entries.
  List<Widget> _buildScheduleGroups(
    BuildContext context,
    List<ProgramScheduleEntry> entries,
    bool isOwner,
  ) {
    final indexed = [
      for (var i = 0; i < entries.length; i++) (index: i, entry: entries[i]),
    ];
    indexed.sort((a, b) {
      final byDay = a.entry.dayOffset.compareTo(b.entry.dayOffset);
      return byDay != 0
          ? byDay
          : a.entry.sortOrder.compareTo(b.entry.sortOrder);
    });

    final widgets = <Widget>[];
    int? currentDay;
    for (final item in indexed) {
      if (item.entry.dayOffset != currentDay) {
        currentDay = item.entry.dayOffset;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(
              _dayLabel(item.entry.dayOffset),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
      final idx = item.index;
      widgets.add(
        _WorkoutCard(
          key: ValueKey(
            '${item.entry.workoutTemplateId}_${item.entry.sortOrder}',
          ),
          workout: item.entry,
          isOwner: isOwner,
          onEditDay: isOwner
              ? () async {
                  final newOffset =
                      await _pickDayOffset(initial: item.entry.dayOffset);
                  if (newOffset != null) {
                    ref
                        .read(programDraftProvider.notifier)
                        .setDayOffset(idx, newOffset);
                  }
                }
              : null,
          onRemove: isOwner
              ? () =>
                  ref.read(programDraftProvider.notifier).removeAt(idx)
              : null,
        ),
      );
    }
    return widgets;
  }

  Widget _buildFolderSelector() {
    final foldersAsync = ref.watch(programFoldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];
    final value = folders.any((f) => f.id == _folderId) ? _folderId : null;
    return DropdownButtonFormField<String?>(
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
      final enrollments =
          await enrollmentRepo.watchEnrollments(widget.programId!, ownerId: uid).first;
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
    await repo.updateType(
      id: widget.programId!,
      type: newType,
      userId: uid,
    );
    if (mounted) setState(() => _programType = newType);
  }

  Future<void> _deleteProgram() async {
    // Block deletion if athletes are enrolled
    if (_programType == ProgramType.assignable) {
      final uid = ref.read(authStateProvider).value?.uid;
      if (uid == null) return;
      final enrollmentRepo = ref.read(enrollmentRepositoryProvider);
      final enrollments =
          await enrollmentRepo.watchEnrollments(widget.programId!, ownerId: uid).first;
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

    await ref.read(programRepositoryProvider).softDelete(
      widget.programId!,
      uid,
    );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing && !_didLoad) {
      _loadExisting();
    }

    final workouts = ref.watch(programDraftProvider);

    if (!widget.isEditing) {
      return _buildCreationForm();
    }

    final uid = ref.watch(authStateProvider).value?.uid;
    final isOwner = _ownerId != null && _ownerId == uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwner ? 'Program Builder' : 'Program Details'),
        actions: [
          if (isOwner && _programType == ProgramType.assignable)
            IconButton(
              icon: const Icon(Icons.group),
              tooltip: 'Manage roster',
              onPressed: () => context.push(
                '/programs/${widget.programId}/roster',
              ),
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
      body: ListView(
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
          const SizedBox(height: 24),
          // Schedule (relative day offsets)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Schedule',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (isOwner)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _generateRecurring,
                      icon: const Icon(Icons.repeat, size: 18),
                      label: const Text('Recurring'),
                    ),
                    TextButton.icon(
                      onPressed: _addWorkout,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
            ],
          ),
          if (workouts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('No workouts scheduled yet'),
              ),
            )
          else
            ..._buildScheduleGroups(context, workouts, isOwner),
          // Inline roster section (assignable programs, owner only)
          if (_programType == ProgramType.assignable && isOwner) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Roster',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (isOwner)
                TextButton.icon(
                  onPressed: () => context.push(
                    '/programs/${widget.programId}/roster',
                  ),
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('Manage'),
                ),
            ],
            ),
            _InlineRoster(
            programId: widget.programId!,
            isOwner: isOwner,
            ),
          ],
        ],
      ),
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
    required super.key,
    required this.workout,
    required this.isOwner,
    this.onEditDay,
    this.onRemove,
  });

  final ProgramScheduleEntry workout;
  final bool isOwner;
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
    return Card(
      child: ListTile(
        title: Text(name),
        subtitle: Text('v${workout.workoutTemplateVersion}'),
        trailing: isOwner
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
    );
  }
}

/// Short weekday name for a 0-based index where 0 = Monday.
String _weekdayName(int day) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day % 7];

/// Human-readable label for a program day offset (0-based, day 0 = Mon).
String _dayLabel(int offset) =>
    'Week ${offset ~/ 7 + 1} · ${_weekdayName(offset % 7)}';

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
                      DropdownMenuItem(
                          value: w, child: Text('Week ${w + 1}')),
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
                      label: Text(_weekdayName(d)),
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

/// Inline roster section shown on the program builder for assignable programs.
class _InlineRoster extends ConsumerWidget {
  const _InlineRoster({
    required this.programId,
    required this.isOwner,
  });

  final String programId;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollmentsAsync = ref.watch(programEnrollmentsProvider(programId));

    return enrollmentsAsync.when(
      data: (enrollments) {
        if (enrollments.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('No athletes enrolled')),
          );
        }
        return Column(
          children: enrollments.map((enrollment) {
            return _InlineAthleteCard(
              programId: programId,
              athleteId: enrollment.athleteId,
              isOwner: isOwner,
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
    );
  }
}

/// Compact athlete card for the inline roster.
///
/// Tapping navigates to the athlete's schedule within this program.
/// Owner sees an assign button.
class _InlineAthleteCard extends ConsumerWidget {
  const _InlineAthleteCard({
    required this.programId,
    required this.athleteId,
    required this.isOwner,
  });

  final String programId;
  final String athleteId;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileRepo = ref.watch(userProfileRepositoryProvider);

    return FutureBuilder(
      future: profileRepo.getUserProfile(athleteId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final displayName = profile?.displayName ?? athleteId;

        return Card(
          child: ListTile(
            leading: profile?.photoUrl != null
                ? CircleAvatar(
                    backgroundImage: NetworkImage(profile!.photoUrl!),
                  )
                : const CircleAvatar(child: Icon(Icons.person)),
            title: Text(displayName),
            trailing: isOwner
                ? IconButton(
                    icon: const Icon(Icons.assignment_add),
                    tooltip: 'Assign workout',
                    onPressed: () => context.push(
                      '/programs/$programId/assign?athleteId=$athleteId',
                    ),
                  )
                : null,
            onTap: () => context.push(
              '/programs/$programId/athlete/$athleteId',
            ),
          ),
        );
      },
    );
  }
}
