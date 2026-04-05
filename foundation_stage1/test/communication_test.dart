import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_stage1/communication.dart';

void main() {
  group('Comment', () {
    test('program-level comment', () {
      final comment = Comment(
        id: 'c1',
        programId: 'prog1',
        athleteId: 'athlete1',
        authorId: 'coach1',
        body: 'Great progress this week!',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'coach1',
      );
      expect(comment.isProgramLevel, isTrue);
      expect(comment.isWorkoutLevel, isFalse);
      expect(comment.isExerciseLevel, isFalse);
      expect(comment.isGroupVisible, isFalse);
      expect(comment.isDeleted, isFalse);
    });

    test('workout-level comment', () {
      final comment = Comment(
        id: 'c2',
        programId: 'prog1',
        workoutInstanceId: 'wi1',
        athleteId: 'athlete1',
        authorId: 'athlete1',
        body: 'This was tough!',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'athlete1',
      );
      expect(comment.isProgramLevel, isFalse);
      expect(comment.isWorkoutLevel, isTrue);
      expect(comment.isExerciseLevel, isFalse);
    });

    test('exercise-level comment', () {
      final comment = Comment(
        id: 'c3',
        programId: 'prog1',
        workoutInstanceId: 'wi1',
        exerciseId: 'ex1',
        athleteId: 'athlete1',
        authorId: 'coach1',
        body: 'Try wider grip next time',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'coach1',
      );
      expect(comment.isProgramLevel, isFalse);
      expect(comment.isWorkoutLevel, isFalse);
      expect(comment.isExerciseLevel, isTrue);
    });

    test('group-visible comment', () {
      final comment = Comment(
        id: 'c4',
        programId: 'prog1',
        workoutInstanceId: 'wi1',
        groupId: 'group1',
        athleteId: 'athlete1',
        authorId: 'athlete1',
        body: 'Group session was fun!',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'athlete1',
      );
      expect(comment.isGroupVisible, isTrue);
    });

    test('comment with media links', () {
      final comment = Comment(
        id: 'c5',
        programId: 'prog1',
        athleteId: 'athlete1',
        authorId: 'athlete1',
        body: 'Check my form',
        mediaLinks: [
          'https://youtube.com/watch?v=abc',
          'https://example.com/photo.jpg',
        ],
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'athlete1',
      );
      expect(comment.mediaLinks!.length, 2);
    });

    test('validate throws on empty body', () {
      final comment = _makeComment(body: '');
      expect(() => comment.validate(), throwsArgumentError);
    });

    test('validate throws when exerciseId set without workoutInstanceId',
        () {
      final comment = Comment(
        id: 'c1',
        programId: 'prog1',
        exerciseId: 'ex1',
        athleteId: 'athlete1',
        authorId: 'coach1',
        body: 'Invalid scope',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'coach1',
      );
      expect(() => comment.validate(), throwsArgumentError);
    });

    test('validate throws on bad audit timestamp order', () {
      final comment = Comment(
        id: 'c1',
        programId: 'prog1',
        athleteId: 'athlete1',
        authorId: 'coach1',
        body: 'Test',
        createdAt: DateTime(2024, 3, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => comment.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid comment', () {
      final comment = _makeComment();
      expect(() => comment.validate(), returnsNormally);
    });
  });

  group('DirectMessageThread', () {
    test('constructor', () {
      final thread = DirectMessageThread(
        id: 'dm1',
        programId: 'prog1',
        athleteId: 'athlete1',
        ownerId: 'coach1',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'coach1',
      );
      expect(thread.id, 'dm1');
      expect(thread.isDeleted, isFalse);
    });

    test('validate throws on empty programId', () {
      final thread = DirectMessageThread(
        id: 'dm1',
        programId: '',
        athleteId: 'athlete1',
        ownerId: 'coach1',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'coach1',
      );
      expect(() => thread.validate(), throwsArgumentError);
    });

    test('validate throws on empty athleteId', () {
      final thread = DirectMessageThread(
        id: 'dm1',
        programId: 'prog1',
        athleteId: '',
        ownerId: 'coach1',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'coach1',
      );
      expect(() => thread.validate(), throwsArgumentError);
    });

    test('validate throws on bad audit timestamp order', () {
      final thread = DirectMessageThread(
        id: 'dm1',
        programId: 'prog1',
        athleteId: 'athlete1',
        ownerId: 'coach1',
        createdAt: DateTime(2024, 3, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => thread.validate(), throwsArgumentError);
    });
  });

  group('Message', () {
    test('constructor and isEdited', () {
      final message = Message(
        id: 'msg1',
        senderId: 'athlete1',
        body: 'Hello coach!',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'athlete1',
      );
      expect(message.id, 'msg1');
      expect(message.isEdited, isFalse);
      expect(message.isDeleted, isFalse);
    });

    test('edited message detected by updatedAt > createdAt', () {
      final message = Message(
        id: 'msg1',
        senderId: 'athlete1',
        body: 'Hello coach! (edited)',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 2, 2),
        updatedBy: 'athlete1',
      );
      expect(message.isEdited, isTrue);
    });

    test('message with media links', () {
      final message = Message(
        id: 'msg1',
        senderId: 'athlete1',
        body: 'Check this video',
        mediaLinks: ['https://youtube.com/watch?v=xyz'],
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'athlete1',
      );
      expect(message.mediaLinks!.length, 1);
    });

    test('validate throws on empty senderId', () {
      final message = Message(
        id: 'msg1',
        senderId: '',
        body: 'Hello',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'athlete1',
      );
      expect(() => message.validate(), throwsArgumentError);
    });

    test('validate throws on empty body', () {
      final message = Message(
        id: 'msg1',
        senderId: 'athlete1',
        body: '',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 2, 1),
        updatedBy: 'athlete1',
      );
      expect(() => message.validate(), throwsArgumentError);
    });

    test('validate throws on bad audit timestamp order', () {
      final message = Message(
        id: 'msg1',
        senderId: 'athlete1',
        body: 'Hello',
        createdAt: DateTime(2024, 3, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'athlete1',
      );
      expect(() => message.validate(), throwsArgumentError);
    });

    test('soft-deleted message', () {
      final message = Message(
        id: 'msg1',
        senderId: 'athlete1',
        body: 'Hello',
        createdAt: DateTime(2024, 2, 1),
        createdBy: 'athlete1',
        updatedAt: DateTime(2024, 3, 1),
        updatedBy: 'system',
        deletedAt: DateTime(2024, 3, 1),
        deletedBy: 'system',
      );
      expect(message.isDeleted, isTrue);
    });
  });
}

/// Helper to create a minimal valid Comment with overrides.
Comment _makeComment({
  String body = 'Great work!',
}) {
  return Comment(
    id: 'c1',
    programId: 'prog1',
    athleteId: 'athlete1',
    authorId: 'coach1',
    body: body,
    createdAt: DateTime(2024, 2, 1),
    createdBy: 'coach1',
    updatedAt: DateTime(2024, 2, 1),
    updatedBy: 'coach1',
  );
}
