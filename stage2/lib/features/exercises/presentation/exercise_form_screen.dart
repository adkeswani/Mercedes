import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage2/features/auth/presentation/auth_providers.dart';
import 'package:stage2/features/exercises/data/exercise_template_repository.dart';
import 'package:stage2/features/exercises/domain/exercise_template.dart';
import 'package:stage2/features/exercises/presentation/exercise_providers.dart';

/// Create or edit an exercise template.
///
/// When [exerciseId] is null, creates a new template.
/// When [exerciseId] is provided, loads and edits an existing one.
class ExerciseFormScreen extends ConsumerStatefulWidget {
  const ExerciseFormScreen({super.key, this.exerciseId});

  final String? exerciseId;

  bool get isEditing => exerciseId != null;

  @override
  ConsumerState<ExerciseFormScreen> createState() => _ExerciseFormScreenState();
}

class _ExerciseFormScreenState extends ConsumerState<ExerciseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _videoUrlController = TextEditingController();

  bool _isLoading = false;
  bool _didLoadExisting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _instructionsController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  void _populateFromTemplate(ExerciseTemplate template) {
    _nameController.text = template.name;
    _descriptionController.text = template.description;
    _instructionsController.text = template.instructions;
    _videoUrlController.text = template.videoUrl ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(exerciseTemplateRepositoryProvider);
      final videoUrl = _videoUrlController.text.trim();

      if (widget.isEditing) {
        await repo.update(
          id: widget.exerciseId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          instructions: _instructionsController.text.trim(),
          userId: uid,
          videoUrl: videoUrl.isEmpty ? null : videoUrl,
        );
      } else {
        await repo.create(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          instructions: _instructionsController.text.trim(),
          userId: uid,
          videoUrl: videoUrl.isEmpty ? null : videoUrl,
        );
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Load existing template for editing
    if (widget.isEditing && !_didLoadExisting) {
      final exercises = ref.watch(exerciseTemplatesProvider);
      exercises.whenData((list) {
        final match = list.where((e) => e.id == widget.exerciseId);
        if (match.isNotEmpty && !_didLoadExisting) {
          _didLoadExisting = true;
          _populateFromTemplate(match.first);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Exercise' : 'New Exercise'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Barbell Back Squat',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Brief description of the exercise',
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Description is required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _instructionsController,
              decoration: const InputDecoration(
                labelText: 'Instructions',
                hintText: 'Step-by-step instructions',
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 5,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Instructions are required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _videoUrlController,
              decoration: const InputDecoration(
                labelText: 'Video URL (optional)',
                hintText: 'https://...',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
      ),
    );
  }
}
