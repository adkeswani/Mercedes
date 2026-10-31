import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/exercise_picker.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/presentation/climbing_grade_field.dart';

/// Total exercise slots currently used across every block in [blocks].
int totalSlotCount(List<WorkoutBlock> blocks) =>
    blocks.fold<int>(0, (sum, block) => sum + block.slots.length);

/// Shows a menu of block types that can be added to the draft, returning
/// the chosen type or null if the user dismisses the sheet.
Future<WorkoutBlockType?> showBlockTypeMenu(BuildContext context) {
  return showModalBottomSheet<WorkoutBlockType>(
    context: context,
    builder: (context) {
      Widget option({
        required WorkoutBlockType type,
        required IconData icon,
        required String title,
        required String subtitle,
      }) {
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: () => Navigator.of(context).pop(type),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Add Block',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              option(
                type: WorkoutBlockType.standardExercise,
                icon: Icons.fitness_center,
                title: 'Standard Exercise',
                subtitle: 'Sets, reps, and weight for a single exercise',
              ),
              option(
                type: WorkoutBlockType.timedInterval,
                icon: Icons.timer_outlined,
                title: 'Timed Interval',
                subtitle: 'Fixed rounds of timed work and rest',
              ),
              option(
                type: WorkoutBlockType.circuit,
                icon: Icons.loop,
                title: 'Circuit',
                subtitle: 'Repeated rounds of multiple exercises',
              ),
              option(
                type: WorkoutBlockType.climbingRoute,
                icon: Icons.terrain,
                title: 'Climbing Route',
                subtitle: 'Canonical grade and target attempts',
              ),
              option(
                type: WorkoutBlockType.climbingCircuit,
                icon: Icons.terrain,
                title: 'Climbing Circuit',
                subtitle: 'Repeatable grade rows for one climbing exercise',
              ),
              option(
                type: WorkoutBlockType.freeClimbing,
                icon: Icons.landscape,
                title: 'Free Climbing',
                subtitle: 'Trainer note; optional athlete grade results',
              ),
              option(
                type: WorkoutBlockType.amrap,
                icon: Icons.hourglass_bottom,
                title: 'AMRAP',
                subtitle: 'As many rounds as possible within a time cap',
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// Opens the creation sheet for [type] and, if the user saves, adds the
/// resulting block to the draft. Returns true if a block was added.
Future<bool> openBlockCreationSheet({
  required BuildContext context,
  required WidgetRef ref,
  required WorkoutBlockType type,
}) async {
  final blocks = ref.read(workoutDraftProvider);
  if (blocks.length >= maxWorkoutBlocksPerVersion) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'A workout supports up to $maxWorkoutBlocksPerVersion blocks',
        ),
      ),
    );
    return false;
  }

  final availableSlots =
      maxExercisePrescriptionsPerWorkoutVersion - totalSlotCount(blocks);
  if (availableSlots <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'A workout supports up to '
          '$maxExercisePrescriptionsPerWorkoutVersion exercises',
        ),
      ),
    );
    return false;
  }

  final repo = ref.read(workoutTemplateRepositoryProvider);
  final block = await _showTypedBlockEditor(
    context: context,
    type: type,
    blockId: repo.generateWorkoutBlockId(),
    existing: null,
    maxSlots: availableSlots,
  );
  if (block == null) return false;
  ref.read(workoutDraftProvider.notifier).addBlock(block);
  return true;
}

/// Opens the edit sheet for the block at [index] (any type). Returns true
/// if the block was updated.
Future<bool> openBlockEditSheet({
  required BuildContext context,
  required WidgetRef ref,
  required WorkoutBlock block,
  required int index,
}) async {
  final blocks = ref.read(workoutDraftProvider);
  final availableSlots = maxExercisePrescriptionsPerWorkoutVersion -
      totalSlotCount(blocks) +
      block.slots.length;
  final updated = await _showTypedBlockEditor(
    context: context,
    type: block.type,
    blockId: block.blockId,
    existing: block,
    maxSlots: availableSlots,
  );
  if (updated == null) return false;
  ref.read(workoutDraftProvider.notifier).updateBlockAt(index, updated);
  return true;
}

Future<WorkoutBlock?> _showTypedBlockEditor({
  required BuildContext context,
  required WorkoutBlockType type,
  required String blockId,
  required WorkoutBlock? existing,
  required int maxSlots,
}) {
  switch (type) {
    case WorkoutBlockType.standardExercise:
      // Standard exercise blocks are created/edited via the exercise
      // picker + prescription editor, not this typed-block sheet.
      return Future.value(null);
    case WorkoutBlockType.timedInterval:
      return showModalBottomSheet<WorkoutBlock>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _TimedIntervalEditorSheet(
          blockId: blockId,
          existing: existing as TimedIntervalBlock?,
          maxSlots: maxSlots,
        ),
      );
    case WorkoutBlockType.circuit:
      return showModalBottomSheet<WorkoutBlock>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _CircuitEditorSheet(
          blockId: blockId,
          existing: existing as CircuitBlock?,
          maxSlots: maxSlots,
        ),
      );
    case WorkoutBlockType.climbingRoute:
    case WorkoutBlockType.climbingCircuit:
    case WorkoutBlockType.freeClimbing:
      return showModalBottomSheet<WorkoutBlock>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _ClimbingEditorSheet(
          blockId: blockId,
          existing: existing,
          type: type,
        ),
      );
    case WorkoutBlockType.amrap:
      return showModalBottomSheet<WorkoutBlock>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _AmrapEditorSheet(
          blockId: blockId,
          existing: existing as AmrapBlock?,
          maxSlots: maxSlots,
        ),
      );
  }
}

int? _parseInt(String text) => int.tryParse(text.trim());

/// Shared list editor for the exercises within a timed interval, circuit,
/// or AMRAP block: lets the trainer add/remove exercises via the shared
/// exercise picker, optionally editing per-exercise sets/reps.
class _ExerciseSlotListField extends ConsumerStatefulWidget {
  const _ExerciseSlotListField({
    required this.slots,
    required this.mode,
    required this.maxSlots,
    required this.onChanged,
    this.showSetsReps = false,
  });

  final List<ExerciseSlot> slots;
  final ExerciseMode mode;
  final int maxSlots;
  final bool showSetsReps;
  final ValueChanged<List<ExerciseSlot>> onChanged;

  @override
  ConsumerState<_ExerciseSlotListField> createState() =>
      _ExerciseSlotListFieldState();
}

class _ExerciseSlotListFieldState
    extends ConsumerState<_ExerciseSlotListField> {
  late List<ExerciseSlot> _slots;

  @override
  void initState() {
    super.initState();
    _slots = List.of(widget.slots);
  }

  Future<void> _addExercise() async {
    if (_slots.length >= widget.maxSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A workout supports up to '
            '$maxExercisePrescriptionsPerWorkoutVersion exercises',
          ),
        ),
      );
      return;
    }
    final result = await showExercisePicker(context, ref);
    if (result == null) return;
    final repo = ref.read(workoutTemplateRepositoryProvider);
    setState(() {
      _slots = [
        ..._slots,
        ExerciseSlot(
          slotId: repo.generateExerciseSlotId(),
          exerciseId: result.id,
          exerciseVersion: result.version,
          exerciseName: result.name,
          sortOrder: _slots.length,
          mode: widget.mode,
        ),
      ];
    });
    widget.onChanged(_slots);
  }

  void _removeAt(int index) {
    setState(() {
      final updated = List.of(_slots)..removeAt(index);
      _slots = [
        for (var i = 0; i < updated.length; i++)
          updated[i].copyWith(sortOrder: i),
      ];
    });
    widget.onChanged(_slots);
  }

  void _updateAt(int index, ExerciseSlot slot) {
    setState(() {
      final updated = List.of(_slots);
      updated[index] = slot;
      _slots = updated;
    });
    widget.onChanged(_slots);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Exercises',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            TextButton.icon(
              onPressed: _addExercise,
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
          ],
        ),
        if (_slots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No exercises added yet'),
          )
        else
          for (var index = 0; index < _slots.length; index++)
            _ExerciseSlotRow(
              key: ValueKey(_slots[index].slotId),
              slot: _slots[index],
              showSetsReps: widget.showSetsReps,
              onChanged: (slot) => _updateAt(index, slot),
              onRemove: () => _removeAt(index),
            ),
      ],
    );
  }
}

class _ExerciseSlotRow extends StatefulWidget {
  const _ExerciseSlotRow({
    required super.key,
    required this.slot,
    required this.showSetsReps,
    required this.onChanged,
    required this.onRemove,
  });

  final ExerciseSlot slot;
  final bool showSetsReps;
  final ValueChanged<ExerciseSlot> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ExerciseSlotRow> createState() => _ExerciseSlotRowState();
}

class _ExerciseSlotRowState extends State<_ExerciseSlotRow> {
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;

  @override
  void initState() {
    super.initState();
    _setsController =
        TextEditingController(text: widget.slot.sets?.toString() ?? '');
    _repsController = TextEditingController(text: widget.slot.reps ?? '');
  }

  @override
  void dispose() {
    _setsController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.slot.copyWith(
        sets: _setsController.text.trim().isEmpty
            ? null
            : int.tryParse(_setsController.text),
        reps: _repsController.text.trim().isEmpty
            ? null
            : _repsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.slot.exerciseName ?? widget.slot.exerciseId),
                if (widget.showSetsReps)
                  Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: _setsController,
                          decoration: const InputDecoration(labelText: 'Sets'),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _emit(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: _repsController,
                          decoration: const InputDecoration(labelText: 'Reps'),
                          onChanged: (_) => _emit(),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove exercise',
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}

/// Wraps sheet content with a title, scroll support, and a Save button.
class _EditorScaffold extends StatelessWidget {
  const _EditorScaffold({
    required this.title,
    required this.children,
    required this.onSave,
    required this.saveEnabled,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saveEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saveEnabled ? onSave : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimedIntervalEditorSheet extends StatefulWidget {
  const _TimedIntervalEditorSheet({
    required this.blockId,
    required this.existing,
    required this.maxSlots,
  });

  final String blockId;
  final TimedIntervalBlock? existing;
  final int maxSlots;

  @override
  State<_TimedIntervalEditorSheet> createState() =>
      _TimedIntervalEditorSheetState();
}

class _TimedIntervalEditorSheetState extends State<_TimedIntervalEditorSheet> {
  late final TextEditingController _roundsController;
  late final TextEditingController _workController;
  late final TextEditingController _restController;
  late List<ExerciseSlot> _slots;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _roundsController =
        TextEditingController(text: (existing?.rounds ?? 8).toString());
    _workController =
        TextEditingController(text: (existing?.workSeconds ?? 30).toString());
    _restController =
        TextEditingController(text: (existing?.restSeconds ?? 15).toString());
    _slots = List.of(existing?.slots ?? const []);
  }

  @override
  void dispose() {
    _roundsController.dispose();
    _workController.dispose();
    _restController.dispose();
    super.dispose();
  }

  void _save() {
    final slots = _slots;
    if (slots.isEmpty) return;
    Navigator.of(context).pop(
      TimedIntervalBlock(
        blockId: widget.blockId,
        sortOrder: 0,
        slots: slots,
        rounds: _parseInt(_roundsController.text) ?? 1,
        workSeconds: _parseInt(_workController.text) ?? 1,
        restSeconds: _parseInt(_restController.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _EditorScaffold(
      title: 'Timed Interval',
      saveEnabled: _slots.isNotEmpty,
      onSave: _save,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _roundsController,
                decoration: const InputDecoration(labelText: 'Rounds'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _workController,
                decoration: const InputDecoration(labelText: 'Work (sec)'),
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
        const SizedBox(height: 16),
        _ExerciseSlotListField(
          slots: _slots,
          mode: ExerciseMode.time,
          maxSlots: widget.maxSlots,
          onChanged: (slots) => setState(() => _slots = slots),
        ),
      ],
    );
  }
}

class _CircuitEditorSheet extends StatefulWidget {
  const _CircuitEditorSheet({
    required this.blockId,
    required this.existing,
    required this.maxSlots,
  });

  final String blockId;
  final CircuitBlock? existing;
  final int maxSlots;

  @override
  State<_CircuitEditorSheet> createState() => _CircuitEditorSheetState();
}

class _CircuitEditorSheetState extends State<_CircuitEditorSheet> {
  late final TextEditingController _roundsController;
  late final TextEditingController _restBetweenRoundsController;
  late List<ExerciseSlot> _slots;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _roundsController =
        TextEditingController(text: (existing?.rounds ?? 3).toString());
    _restBetweenRoundsController = TextEditingController(
      text: (existing?.restBetweenRoundsSeconds ?? 60).toString(),
    );
    _slots = List.of(existing?.slots ?? const []);
  }

  @override
  void dispose() {
    _roundsController.dispose();
    _restBetweenRoundsController.dispose();
    super.dispose();
  }

  void _save() {
    final slots = _slots;
    if (slots.isEmpty) return;
    Navigator.of(context).pop(
      CircuitBlock(
        blockId: widget.blockId,
        sortOrder: 0,
        slots: slots,
        rounds: _parseInt(_roundsController.text) ?? 1,
        restBetweenRoundsSeconds:
            _parseInt(_restBetweenRoundsController.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _EditorScaffold(
      title: 'Circuit',
      saveEnabled: _slots.isNotEmpty,
      onSave: _save,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _roundsController,
                decoration: const InputDecoration(labelText: 'Rounds'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _restBetweenRoundsController,
                decoration: const InputDecoration(
                  labelText: 'Rest between rounds (sec)',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ExerciseSlotListField(
          slots: _slots,
          mode: ExerciseMode.reps,
          maxSlots: widget.maxSlots,
          showSetsReps: true,
          onChanged: (slots) => setState(() => _slots = slots),
        ),
      ],
    );
  }
}

class _AmrapEditorSheet extends StatefulWidget {
  const _AmrapEditorSheet({
    required this.blockId,
    required this.existing,
    required this.maxSlots,
  });

  final String blockId;
  final AmrapBlock? existing;
  final int maxSlots;

  @override
  State<_AmrapEditorSheet> createState() => _AmrapEditorSheetState();
}

class _AmrapEditorSheetState extends State<_AmrapEditorSheet> {
  late final TextEditingController _timeCapController;
  late List<ExerciseSlot> _slots;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _timeCapController = TextEditingController(
      text: (existing?.timeCapSeconds ?? 600).toString(),
    );
    _slots = List.of(existing?.slots ?? const []);
  }

  @override
  void dispose() {
    _timeCapController.dispose();
    super.dispose();
  }

  void _save() {
    final slots = _slots;
    if (slots.isEmpty) return;
    Navigator.of(context).pop(
      AmrapBlock(
        blockId: widget.blockId,
        sortOrder: 0,
        slots: slots,
        timeCapSeconds: _parseInt(_timeCapController.text) ?? 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _EditorScaffold(
      title: 'AMRAP',
      saveEnabled: _slots.isNotEmpty,
      onSave: _save,
      children: [
        TextField(
          controller: _timeCapController,
          decoration: const InputDecoration(labelText: 'Time cap (sec)'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        _ExerciseSlotListField(
          slots: _slots,
          mode: ExerciseMode.amrap,
          maxSlots: widget.maxSlots,
          onChanged: (slots) => setState(() => _slots = slots),
        ),
      ],
    );
  }
}

class _ClimbingEditorSheet extends ConsumerStatefulWidget {
  const _ClimbingEditorSheet({
    required this.blockId,
    required this.existing,
    required this.type,
  });

  final String blockId;
  final WorkoutBlock? existing;
  final WorkoutBlockType type;

  @override
  ConsumerState<_ClimbingEditorSheet> createState() =>
      _ClimbingEditorSheetState();
}

class _ClimbingEditorSheetState extends ConsumerState<_ClimbingEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _targetAttemptsController;
  late final TextEditingController _notesController;
  final List<_ClimbingRowInput> _rows = [];
  ClimbingGradingSystem _system = ClimbingGradingSystem.vScale;
  String _grade = 'V0';
  bool _gradeChosen = true;
  String? _error;
  ExerciseSlot? _route;
  bool get _isFree => widget.type == WorkoutBlockType.freeClimbing;
  bool get _isCircuit => widget.type == WorkoutBlockType.climbingCircuit;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _targetAttemptsController = TextEditingController(
      text: existing is ClimbingRouteBlock
          ? existing.targetAttempts?.toString() ?? ''
          : '',
    );
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _route = existing?.slots.single;
    if (existing is ClimbingRouteBlock) {
      _gradeChosen = existing.gradingSystem != null;
      if (_gradeChosen) {
        _system = existing.gradingSystem!;
        _grade = existing.grade;
      }
    }
    if (existing is ClimbingCircuitBlock) {
      _rows.addAll(existing.rows.map(_ClimbingRowInput.fromRow));
    } else if (_isCircuit) {
      _addRow();
    }
  }

  @override
  void dispose() {
    _targetAttemptsController.dispose();
    _notesController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _pickRoute() async {
    final result = await showExercisePicker(context, ref);
    if (result == null) return;
    final repo = ref.read(workoutTemplateRepositoryProvider);
    setState(() {
      _route = ExerciseSlot(
        slotId: _route?.slotId ?? repo.generateExerciseSlotId(),
        exerciseId: result.id,
        exerciseVersion: result.version,
        exerciseName: result.name,
        sortOrder: 0,
        mode: ExerciseMode.reps,
      );
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_isFree && _route == null) {
      setState(() => _error = 'Choose the climbing exercise');
      return;
    }
    if (!_isFree && !_isCircuit && !_gradeChosen) {
      setState(() =>
          _error = 'Choose a canonical grade before saving this legacy route');
      return;
    }
    try {
      final notes = _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim();
      final WorkoutBlock block = _isFree
          ? FreeClimbingBlock(
              blockId: widget.blockId,
              sortOrder: widget.existing?.sortOrder ?? 0,
              slotId: _route?.slotId ??
                  ref
                      .read(workoutTemplateRepositoryProvider)
                      .generateExerciseSlotId(),
              notes: notes,
              title: widget.existing?.title,
            )
          : _isCircuit
              ? ClimbingCircuitBlock(
                  blockId: widget.blockId,
                  sortOrder: widget.existing?.sortOrder ?? 0,
                  exercise: _route!,
                  rows: _rows.map((r) => r.toRow()).toList(),
                  notes: notes,
                  title: widget.existing?.title,
                )
              : ClimbingRouteBlock(
                  blockId: widget.blockId,
                  sortOrder: widget.existing?.sortOrder ?? 0,
                  route: _route!,
                  grade: _grade,
                  gradingSystem: _system,
                  targetAttempts: _targetAttemptsController.text.trim().isEmpty
                      ? null
                      : int.parse(_targetAttemptsController.text.trim()),
                  notes: notes,
                  title: widget.existing?.title,
                );
      block.validate();
      Navigator.of(context).pop(block);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _addRow() {
    _rows.add(_ClimbingRowInput(
      ref.read(workoutTemplateRepositoryProvider).generateExerciseSlotId(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    return Form(
        key: _formKey,
        child: _EditorScaffold(
          title: _isFree
              ? 'Free Climbing'
              : _isCircuit
                  ? 'Climbing Circuit'
                  : 'Climbing Route',
          saveEnabled: true,
          onSave: _save,
          children: [
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!_isFree)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(route?.exerciseName ?? 'No exercise selected'),
                trailing: TextButton(
                  onPressed: _pickRoute,
                  child: Text(route == null ? 'Choose exercise' : 'Change'),
                ),
              ),
            const SizedBox(height: 8),
            if (!_isFree && !_isCircuit) ...[
              if (!_gradeChosen)
                const Text(
                    'Legacy grade/color remains in published history. Select a canonical grade for this edit.'),
              ClimbingGradeField(
                system: _system,
                grade: _grade,
                onChanged: (system, grade) => setState(() {
                  _system = system;
                  _grade = grade;
                  _gradeChosen = true;
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _targetAttemptsController,
                decoration: const InputDecoration(
                    labelText: 'Target attempts (optional)'),
                keyboardType: TextInputType.number,
                validator: (value) => _positiveInteger(value, optional: true),
              ),
            ],
            if (_isCircuit) ...[
              for (final row in _rows)
                Card(
                  key: ValueKey(row.rowId),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClimbingGradeField(
                          system: row.system,
                          grade: row.grade,
                          onChanged: (system, grade) => setState(() {
                            row.system = system;
                            row.grade = grade;
                          }),
                        ),
                        TextFormField(
                          controller: row.climbs,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Number of climbs'),
                          validator: (value) => _positiveInteger(value),
                        ),
                        TextFormField(
                          controller: row.attempts,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Max attempts per climb (optional)'),
                          validator: (value) =>
                              _positiveInteger(value, optional: true),
                        ),
                        TextFormField(
                          controller: row.notes,
                          decoration: const InputDecoration(
                              labelText: 'Row note (optional)'),
                          maxLength: 4000,
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _rows.remove(row);
                            row.dispose();
                          }),
                          child: const Text('Remove climbing row'),
                        ),
                      ],
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: _rows.length < maxClimbingRows
                    ? () => setState(_addRow)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add climbing row'),
              ),
              const Text(
                  'Max attempts applies to each climb, not the whole row. Up to 9 rows share one exercise slot.'),
            ],
            TextFormField(
              controller: _notesController,
              decoration:
                  const InputDecoration(labelText: 'Trainer note (optional)'),
              maxLength: 4000,
            ),
          ],
        ));
  }
}

String? _positiveInteger(String? value, {bool optional = false}) {
  final text = value?.trim() ?? '';
  if (optional && text.isEmpty) return null;
  final parsed = int.tryParse(text);
  return parsed == null || parsed < 1 ? 'Enter a positive whole number' : null;
}

class _ClimbingRowInput {
  _ClimbingRowInput(this.rowId);
  factory _ClimbingRowInput.fromRow(ClimbingCircuitRow row) {
    return _ClimbingRowInput(row.rowId)
      ..system = row.gradingSystem
      ..grade = row.grade
      ..climbs.text = row.climbs.toString()
      ..attempts.text = row.maxAttemptsPerClimb?.toString() ?? ''
      ..notes.text = row.notes ?? '';
  }
  final String rowId;
  ClimbingGradingSystem system = ClimbingGradingSystem.vScale;
  String grade = 'V0';
  final climbs = TextEditingController();
  final attempts = TextEditingController();
  final notes = TextEditingController();
  ClimbingCircuitRow toRow() => ClimbingCircuitRow(
        rowId: rowId,
        gradingSystem: system,
        grade: grade,
        climbs: int.parse(climbs.text.trim()),
        maxAttemptsPerClimb: attempts.text.trim().isEmpty
            ? null
            : int.parse(attempts.text.trim()),
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
  void dispose() {
    climbs.dispose();
    attempts.dispose();
    notes.dispose();
  }
}
