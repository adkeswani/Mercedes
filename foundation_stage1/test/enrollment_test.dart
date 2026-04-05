import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_stage1/enrollment.dart';
import 'package:foundation_stage1/enums.dart';

void main() {
  group('Enrollment', () {
    test('constructor and convenience getters for active enrollment', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: 'prog1',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 1, 1),
        addedBy: 'coach1',
        status: EnrollmentStatus.active,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(enrollment.isActive, isTrue);
      expect(enrollment.isRemoved, isFalse);
      expect(enrollment.isDeleted, isFalse);
    });

    test('removed enrollment with lifecycle timestamps', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: 'prog1',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 1, 1),
        addedBy: 'coach1',
        removedAt: DateTime(2024, 3, 1),
        removedBy: 'coach1',
        status: EnrollmentStatus.removed,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 3, 1),
        updatedBy: 'coach1',
      );
      expect(enrollment.isActive, isFalse);
      expect(enrollment.isRemoved, isTrue);
    });

    test('validate throws on empty programId', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: '',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 1, 1),
        addedBy: 'coach1',
        status: EnrollmentStatus.active,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => enrollment.validate(), throwsArgumentError);
    });

    test('validate throws when removed without removedAt', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: 'prog1',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 1, 1),
        addedBy: 'coach1',
        status: EnrollmentStatus.removed,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => enrollment.validate(), throwsArgumentError);
    });

    test('validate throws when removed without removedBy', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: 'prog1',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 1, 1),
        addedBy: 'coach1',
        removedAt: DateTime(2024, 3, 1),
        status: EnrollmentStatus.removed,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => enrollment.validate(), throwsArgumentError);
    });

    test('validate throws when addedAt > removedAt', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: 'prog1',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 6, 1),
        addedBy: 'coach1',
        removedAt: DateTime(2024, 3, 1),
        removedBy: 'coach1',
        status: EnrollmentStatus.removed,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 6, 1),
        updatedBy: 'coach1',
      );
      expect(() => enrollment.validate(), throwsArgumentError);
    });

    test('validate throws on bad audit timestamp order', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: 'prog1',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 1, 1),
        addedBy: 'coach1',
        status: EnrollmentStatus.active,
        createdAt: DateTime(2024, 3, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => enrollment.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid active enrollment', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: 'prog1',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 1, 1),
        addedBy: 'coach1',
        status: EnrollmentStatus.active,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => enrollment.validate(), returnsNormally);
    });

    test('validate succeeds for valid removed enrollment', () {
      final enrollment = Enrollment(
        id: 'enr1',
        programId: 'prog1',
        athleteId: 'athlete1',
        addedAt: DateTime(2024, 1, 1),
        addedBy: 'coach1',
        removedAt: DateTime(2024, 3, 1),
        removedBy: 'coach1',
        status: EnrollmentStatus.removed,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 3, 1),
        updatedBy: 'coach1',
      );
      expect(() => enrollment.validate(), returnsNormally);
    });
  });
}
