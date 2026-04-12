import 'package:flutter_test/flutter_test.dart';
import 'package:stage2/features/auth/domain/foundation_models.dart';

void main() {
  group('Admin', () {
    test('constructor and isDeleted', () {
      final admin = Admin(
        id: 'admin1',
        email: 'admin@example.com',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'system',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'system',
      );
      expect(admin.id, 'admin1');
      expect(admin.isDeleted, isFalse);
    });

    test('isDeleted true when deletedAt is set', () {
      final admin = Admin(
        id: 'admin2',
        email: 'admin2@example.com',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'system',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'system',
        deletedAt: DateTime(2024, 2, 1),
        deletedBy: 'system',
      );
      expect(admin.isDeleted, isTrue);
    });

    test('validate throws on empty id', () {
      final admin = Admin(
        id: '',
        email: 'admin@example.com',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'system',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'system',
      );
      expect(() => admin.validate(), throwsArgumentError);
    });
  });

  group('ProgramRole', () {
    test('constructor and isDeleted', () {
      final role = ProgramRole(
        userId: 'user1',
        programId: 'prog1',
        role: UserRole.athlete,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
      expect(role.userId, 'user1');
      expect(role.isDeleted, isFalse);
    });

    test('validate throws on empty userId', () {
      final role = ProgramRole(
        userId: '',
        programId: 'prog1',
        role: UserRole.athlete,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
      expect(() => role.validate(), throwsArgumentError);
    });
  });

  group('ProgramEnrollment', () {
    test('constructor and isDeleted', () {
      final enrollment = ProgramEnrollment(
        userId: 'user1',
        programId: 'prog1',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
      expect(enrollment.userId, 'user1');
      expect(enrollment.isDeleted, isFalse);
    });

    test('validate throws on empty programId', () {
      final enrollment = ProgramEnrollment(
        userId: 'user1',
        programId: '',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
      expect(() => enrollment.validate(), throwsArgumentError);
    });
  });

  group('ExerciseTemplate', () {
    test('constructor and isDeleted', () {
      final template = ExerciseTemplate(
        id: 'ex1',
        name: 'Pushup',
        description: 'Standard pushup exercise',
        instructions: 'Keep body straight, lower chest to floor',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
      expect(template.id, 'ex1');
      expect(template.isDeleted, isFalse);
    });

    test('validate throws on empty description', () {
      final template = ExerciseTemplate(
        id: 'ex1',
        name: 'Pushup',
        description: '',
        instructions: 'Do it',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
      expect(() => template.validate(), throwsArgumentError);
    });

    test('validate throws on empty instructions', () {
      final template = ExerciseTemplate(
        id: 'ex1',
        name: 'Pushup',
        description: 'A pushup',
        instructions: '',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
      expect(() => template.validate(), throwsArgumentError);
    });

    test('videoUrl is optional', () {
      final template = ExerciseTemplate(
        id: 'ex1',
        name: 'Pushup',
        description: 'Standard pushup',
        videoUrl: 'https://example.com/video.mp4',
        instructions: 'Do pushups',
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
      expect(template.videoUrl, 'https://example.com/video.mp4');
    });
  });
}
