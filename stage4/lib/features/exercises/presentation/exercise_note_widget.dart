import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage4/features/exercises/presentation/exercise_note_providers.dart';

/// Inline widget for viewing and editing a personal exercise note.
///
/// Shows a compact note indicator when collapsed. Expands to a text
/// field for editing. Saves on submit, deletes when cleared.
class ExerciseNoteWidget extends ConsumerStatefulWidget {
  const ExerciseNoteWidget({
    super.key,
    required this.exerciseTemplateId,
    required this.exerciseName,
  });

  final String exerciseTemplateId;
  final String exerciseName;

  @override
  ConsumerState<ExerciseNoteWidget> createState() =>
      _ExerciseNoteWidgetState();
}

class _ExerciseNoteWidgetState extends ConsumerState<ExerciseNoteWidget> {
  bool _isEditing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(exerciseNoteRepositoryProvider);
    if (repo == null) return;

    final text = _controller.text.trim();
    if (text.isEmpty) {
      await repo.deleteNote(widget.exerciseTemplateId);
    } else {
      await repo.saveNote(
        exerciseTemplateId: widget.exerciseTemplateId,
        exerciseName: widget.exerciseName,
        note: text,
      );
    }
    if (mounted) setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(exerciseNotesProvider);
    final note = notesAsync.valueOrNull?[widget.exerciseTemplateId];

    if (_isEditing) {
      return _buildEditor(context, note?.note);
    }

    if (note != null) {
      return _buildNotePreview(context, note.note);
    }

    return _buildAddButton(context);
  }

  Widget _buildAddButton(BuildContext context) {
    return InkWell(
      onTap: () {
        _controller.text = '';
        setState(() => _isEditing = true);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              'Add personal note',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotePreview(BuildContext context, String noteText) {
    return InkWell(
      onTap: () {
        _controller.text = noteText;
        setState(() => _isEditing = true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              Icons.sticky_note_2,
              size: 16,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                noteText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.tertiary,
                      fontStyle: FontStyle.italic,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.edit,
              size: 14,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, String? existingNote) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Your personal note on this exercise...',
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: existingNote != null
                ? IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete note',
                    onPressed: () {
                      _controller.clear();
                      _save();
                    },
                  )
                : null,
          ),
          maxLines: 3,
          minLines: 1,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _isEditing = false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _save,
              child: const Text('Save Note'),
            ),
          ],
        ),
      ],
    );
  }
}
