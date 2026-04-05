import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_stage1/goal.dart';

void main() {
  group('Goal', () {
    test('constructor with defaults', () {
      final goal = Goal(
        id: 'g1',
        athleteId: 'athlete1',
        title: 'Send V8 by June',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      expect(goal.id, 'g1');
      expect(goal.isDone, isFalse);
      expect(goal.hasDueDate, isFalse);
      expect(goal.completed, isFalse);
    });

    test('goal with due date', () {
      final goal = Goal(
        id: 'g1',
        athleteId: 'athlete1',
        title: 'Complete program',
        dueDate: '2026-06-01',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      expect(goal.hasDueDate, isTrue);
      expect(goal.dueDate, '2026-06-01');
    });

    test('completed goal', () {
      final goal = Goal(
        id: 'g1',
        athleteId: 'athlete1',
        title: 'Send V8',
        completed: true,
        completedAt: DateTime(2024, 3, 15),
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 3, 15),
      );
      expect(goal.isDone, isTrue);
    });

    test('goal with notes', () {
      final goal = Goal(
        id: 'g1',
        athleteId: 'athlete1',
        title: 'Improve finger strength',
        notes: 'Focus on half-crimp hangs',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      expect(goal.notes, 'Focus on half-crimp hangs');
    });

    test('validate throws on empty id', () {
      final goal = _makeGoal(id: '');
      expect(() => goal.validate(), throwsArgumentError);
    });

    test('validate throws on empty athleteId', () {
      final goal = _makeGoal(athleteId: '');
      expect(() => goal.validate(), throwsArgumentError);
    });

    test('validate throws on empty title', () {
      final goal = _makeGoal(title: '');
      expect(() => goal.validate(), throwsArgumentError);
    });

    test('validate throws on bad timestamp order', () {
      final goal = Goal(
        id: 'g1',
        athleteId: 'athlete1',
        title: 'Test',
        createdAt: DateTime(2024, 3, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      expect(() => goal.validate(), throwsArgumentError);
    });

    test('validate throws on invalid dueDate format', () {
      final goal = Goal(
        id: 'g1',
        athleteId: 'athlete1',
        title: 'Test',
        dueDate: '2024/06/01',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      expect(() => goal.validate(), throwsArgumentError);
    });

    test('validate throws when completed without completedAt', () {
      final goal = Goal(
        id: 'g1',
        athleteId: 'athlete1',
        title: 'Test',
        completed: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      expect(() => goal.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid goal', () {
      final goal = _makeGoal();
      expect(() => goal.validate(), returnsNormally);
    });

    test('validate succeeds for valid completed goal', () {
      final goal = Goal(
        id: 'g1',
        athleteId: 'athlete1',
        title: 'Send V8',
        completed: true,
        completedAt: DateTime(2024, 3, 15),
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 3, 15),
      );
      expect(() => goal.validate(), returnsNormally);
    });
  });
}

/// Helper to create a minimal valid Goal with overrides.
Goal _makeGoal({
  String id = 'g1',
  String athleteId = 'athlete1',
  String title = 'Send V8',
}) {
  return Goal(
    id: id,
    athleteId: athleteId,
    title: title,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );
}
