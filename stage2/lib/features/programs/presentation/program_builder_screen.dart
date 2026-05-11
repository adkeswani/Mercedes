import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage2/core/enums.dart';
import 'package:stage2/features/auth/presentation/auth_providers.dart';
import 'package:stage2/features/programs/domain/program.dart';
import 'package:stage2/features/programs/presentation/program_providers.dart';
import 'package:stage2/features/programs/presentation/workout_picker.dart';
import 'package:stage2/features/workouts/presentation/workout_providers.dart';

/// Builder screen for creating/editing a program.
///
/// Collects header info (name, description, type) and manages a local draft
/// of workout references. Changes are only persisted on Publish.
class ProgramBuilderScreen extends ConsumerStatefulWidget {
  const ProgramBuilderScreen({super.key, this.programId});

  final String? programId;

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
    setState(() => _programType = program.type);

    // Load latest version's workouts into draft
    if (program.currentVersion > 0) {
      final version = await repo.getVersion(
        widget.programId!,
        program.currentVersion,
      );
      if (version != null && mounted) {
        ref.read(programDraftProvider.notifier).load(version.workouts);
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
      final repo = ref.read(programRepositoryProvider);
      final id = await repo.create(
        name: _nameController.text.trim(),
        type: _programType,
        userId: uid,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );
      if (mounted) {
        context.go('/programs/$id');
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
        workouts: workouts,
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
    if (result == null) return;

    final workouts = ref.read(programDraftProvider);
    ref.read(programDraftProvider.notifier).addWorkout(
      ProgramWorkoutRef(
        workoutTemplateId: result.id,
        workoutTemplateVersion: result.currentVersion,
        sortOrder: workouts.length,
      ),
    );
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Program Builder'),
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
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Program Name'),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => _saveHeader(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
            maxLines: 3,
            onChanged: (_) => _saveHeader(),
          ),
          const SizedBox(height: 24),
          // Workout list
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Workouts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton.icon(
                onPressed: _addWorkout,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          if (workouts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('No workouts added yet'),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: workouts.length,
              onReorder: (oldIndex, newIndex) {
                ref.read(programDraftProvider.notifier).reorder(
                  oldIndex,
                  newIndex,
                );
              },
              itemBuilder: (context, index) {
                final workout = workouts[index];
                return _WorkoutCard(
                  key: ValueKey(
                    '${workout.workoutTemplateId}_${workout.sortOrder}',
                  ),
                  workout: workout,
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

/// Card for a single workout in the builder's reorderable list.
class _WorkoutCard extends ConsumerWidget {
  const _WorkoutCard({
    required super.key,
    required this.workout,
    required this.index,
  });

  final ProgramWorkoutRef workout;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve workout name from the templates stream
    final workoutsAsync = ref.watch(workoutTemplatesProvider);
    final name = workoutsAsync.whenOrNull(
      data: (templates) {
        final match = templates
            .where((t) => t.id == workout.workoutTemplateId)
            .toList();
        return match.isNotEmpty ? match.first.name : workout.workoutTemplateId;
      },
    ) ?? workout.workoutTemplateId;

    return Card(
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text(name),
        subtitle: Text('v${workout.workoutTemplateVersion}'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove',
          onPressed: () {
            ref.read(programDraftProvider.notifier).removeAt(index);
          },
        ),
      ),
    );
  }
}
