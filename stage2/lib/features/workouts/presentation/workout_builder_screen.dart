import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage2/core/enums.dart';
import 'package:stage2/features/auth/presentation/auth_providers.dart';
import 'package:stage2/features/workouts/domain/workout_template.dart';
import 'package:stage2/features/workouts/presentation/exercise_picker.dart';
import 'package:stage2/features/workouts/presentation/workout_providers.dart';

/// Builder screen for creating/editing a workout template.
///
/// Collects header info (name, workout type) and manages a local draft
/// of exercise prescriptions. Changes are only persisted on Publish.
class WorkoutBuilderScreen extends ConsumerStatefulWidget {
  const WorkoutBuilderScreen({super.key, this.workoutId});

  final String? workoutId;

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

  Future<void> _loadExisting() async {
    if (_didLoad || !widget.isEditing) return;
    _didLoad = true;

    final repo = ref.read(workoutTemplateRepositoryProvider);
    final template = await repo.getById(widget.workoutId!);
    if (template == null || !mounted) return;

    _nameController.text = template.name;
    setState(() => _workoutType = template.workoutType);

    // Load latest version's exercises into draft
    if (template.hasPublishedVersion) {
      final version = await repo.getVersion(
        widget.workoutId!,
        template.currentVersion,
      );
      if (version != null && mounted) {
        ref.read(workoutDraftProvider.notifier).load(version.exercises);
      }
    }
  }

  Future<void> _createAndEnter() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(workoutTemplateRepositoryProvider);
      final id = await repo.create(
        name: _nameController.text.trim(),
        workoutType: _workoutType,
        userId: uid,
      );
      if (mounted) {
        // Replace the /workouts/new route with /workouts/:id
        context.go('/workouts/$id');
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

    final exercises = ref.read(workoutDraftProvider);
    if (exercises.isEmpty) {
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
        templateId: widget.workoutId!,
        exercises: exercises,
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

  void _addExercise() async {
    final result = await showExercisePicker(context, ref);
    if (result == null) return;

    final exercises = ref.read(workoutDraftProvider);
    ref.read(workoutDraftProvider.notifier).addExercise(
      ExercisePrescription(
        exerciseId: result.id,
        exerciseName: result.name,
        sortOrder: exercises.length,
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

    final exercises = ref.watch(workoutDraftProvider);

    // New template — show creation form
    if (!widget.isEditing) {
      return _buildCreationForm();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Builder'),
        actions: [
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
          // Header fields
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Workout Name'),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => _saveHeader(),
          ),
          const SizedBox(height: 12),
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
              if (value != null) {
                setState(() => _workoutType = value);
                _saveHeader();
              }
            },
          ),
          const SizedBox(height: 24),
          // Exercise list
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Exercises',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton.icon(
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          if (exercises.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('No exercises added yet'),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: exercises.length,
              onReorder: (oldIndex, newIndex) {
                ref.read(workoutDraftProvider.notifier).reorder(
                  oldIndex,
                  newIndex,
                );
              },
              itemBuilder: (context, index) {
                final exercise = exercises[index];
                return _ExerciseCard(
                  key: ValueKey(
                    '${exercise.exerciseId}_${exercise.sortOrder}',
                  ),
                  exercise: exercise,
                  index: index,
                );
              },
            ),
        ],
      ),
    );
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
class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    required super.key,
    required this.exercise,
    required this.index,
  });

  final ExercisePrescription exercise;
  final int index;

  String get _prescriptionSummary {
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
    return Card(
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text(exercise.exerciseName ?? exercise.exerciseId),
        subtitle: Text(_prescriptionSummary),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit prescription',
              onPressed: () => _editPrescription(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: () {
                ref.read(workoutDraftProvider.notifier).removeAt(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editPrescription(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PrescriptionEditor(
        prescription: exercise,
        onSave: (updated) {
          ref.read(workoutDraftProvider.notifier).updateAt(index, updated);
          Navigator.of(context).pop();
        },
      ),
    );
  }
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
      weight:
          _weightController.text.isEmpty ? null : _weightController.text,
      restSeconds: int.tryParse(_restController.text),
      notes:
          _notesController.text.isEmpty ? null : _notesController.text,
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
                  decoration:
                      const InputDecoration(labelText: 'Rest (sec)'),
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
