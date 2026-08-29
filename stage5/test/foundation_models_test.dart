import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/auth/domain/foundation_models.dart';

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
    ExerciseTemplate exercise({
      String description = 'Standard pushup exercise',
      String instructions = 'Keep body straight, lower chest to floor',
      String? videoUrl,
    }) {
      return ExerciseTemplate(
        id: 'ex1',
        ownerId: 'admin',
        currentVersion: 1,
        version: ExerciseVersion(
          versionNumber: 1,
          name: 'Pushup',
          description: description,
          instructions: instructions,
          videoUrl: videoUrl,
          exerciseType: ExerciseType.strength,
          measurementConfiguration: const ExerciseMeasurementConfiguration(
            primary: ExerciseMeasurementType.repetitions,
          ),
          publishedAt: DateTime(2024, 1, 1),
          publishedBy: 'admin',
        ),
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'admin',
      );
    }

    test('constructor and isDeleted', () {
      final template = exercise();
      expect(template.id, 'ex1');
      expect(template.isDeleted, isFalse);
    });

    test('validate throws on empty description', () {
      final template = exercise(description: '', instructions: 'Do it');
      expect(() => template.validate(), throwsArgumentError);
    });

    test('validate throws on empty instructions', () {
      final template = exercise(description: 'A pushup', instructions: '');
      expect(() => template.validate(), throwsArgumentError);
    });

    test('videoUrl is optional', () {
      final template = exercise(
        description: 'Standard pushup',
        instructions: 'Do pushups',
        videoUrl: 'https://example.com/video.mp4',
      );
      expect(template.videoUrl, 'https://example.com/video.mp4');
    });
  });
}
