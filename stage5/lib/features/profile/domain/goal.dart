/// Athlete personal goal with optional due date and completion tracking.
///
/// Goals are private to the athlete and not visible to program owners.
/// Goals with due dates appear on the calendar alongside workouts.
class Goal {

  Goal({
    required this.id,
    required this.athleteId,
    required this.title,
    required this.createdAt, required this.updatedAt, this.notes,
    this.dueDate,
    this.completed = false,
    this.completedAt,
  });
  final String id;
  final String athleteId;
  final String title;
  final String? notes;
  final String? dueDate;
  final bool completed;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether this goal is marked as done.
  bool get isDone => completed;

  /// Whether this goal has a due date.
  bool get hasDueDate => dueDate != null;

  /// Whether this goal is overdue (has a due date, not completed).
  bool get isOverdue {
    if (dueDate == null || completed) {
      return false;
    }

    final due = DateTime.tryParse(dueDate!);
    if (due == null) {
      return false;
    }

    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day)
        .isAfter(DateTime(due.year, due.month, due.day));
  }

  /// Validates all required fields and constraints.
  void validate() {
    if (id.isEmpty) {
      throw ArgumentError('id cannot be empty');
    }
    if (athleteId.isEmpty) {
      throw ArgumentError('athleteId cannot be empty');
    }
    if (title.isEmpty) {
      throw ArgumentError('title cannot be empty');
    }
    if (createdAt.isAfter(updatedAt)) {
      throw ArgumentError('createdAt must be <= updatedAt');
    }

    if (dueDate != null) {
      final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      if (!dateRegex.hasMatch(dueDate!)) {
        throw ArgumentError(
          'dueDate must be ISO 8601 date format (YYYY-MM-DD)',
        );
      }
    }

    if (completed && completedAt == null) {
      throw ArgumentError(
        'completedAt is required when goal is completed',
      );
    }
  }
}
