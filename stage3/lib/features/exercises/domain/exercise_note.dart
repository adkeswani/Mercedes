/// Private per-athlete note on an exercise template.
///
/// Stored at `users/{userId}/exerciseNotes/{exerciseTemplateId}`.
/// Only the owning athlete can read or write their notes.
/// Trainers cannot see athlete notes.
class ExerciseNote {
  ExerciseNote({
    required this.id,
    required this.exerciseTemplateId,
    required this.exerciseName,
    required this.note,
    required this.updatedAt,
  });

  /// Document ID (same as exerciseTemplateId for 1:1 mapping).
  final String id;

  /// The exercise template this note is attached to.
  final String exerciseTemplateId;

  /// Cached exercise name for display without extra lookups.
  final String exerciseName;

  /// The athlete's note text.
  final String note;

  /// When the note was last updated.
  final DateTime updatedAt;

  void validate() {
    if (exerciseTemplateId.isEmpty) {
      throw ArgumentError('exerciseTemplateId cannot be empty');
    }
    if (exerciseName.isEmpty) {
      throw ArgumentError('exerciseName cannot be empty');
    }
    if (note.isEmpty) {
      throw ArgumentError('note cannot be empty');
    }
  }
}
