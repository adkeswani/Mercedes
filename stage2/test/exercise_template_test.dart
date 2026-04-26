import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage2/features/exercises/data/exercise_template_repository.dart';
import 'package:stage2/features/exercises/domain/exercise_template.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late ExerciseTemplateRepository repo;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repo = ExerciseTemplateRepository(firestore: fakeFirestore);
  });

  group('ExerciseTemplate.copyWith', () {
    test('returns a copy with updated fields', () {
      final now = DateTime(2026, 1, 1);
      final template = ExerciseTemplate(
        id: 'ex1',
        name: 'Squat',
        description: 'Barbell squat',
        instructions: 'Place bar on back',
        createdAt: now,
        createdBy: 'user1',
        updatedAt: now,
        updatedBy: 'user1',
      );
      final updated = template.copyWith(name: 'Back Squat');
      expect(updated.name, 'Back Squat');
      expect(updated.id, 'ex1');
      expect(updated.description, 'Barbell squat');
    });

    test('preserves all fields when no arguments given', () {
      final now = DateTime(2026, 1, 1);
      final template = ExerciseTemplate(
        id: 'ex1',
        name: 'Squat',
        description: 'Desc',
        instructions: 'Steps',
        videoUrl: 'https://example.com',
        createdAt: now,
        createdBy: 'user1',
        updatedAt: now,
        updatedBy: 'user1',
      );
      final copy = template.copyWith();
      expect(copy.id, template.id);
      expect(copy.name, template.name);
      expect(copy.videoUrl, template.videoUrl);
    });
  });

  group('ExerciseTemplateRepository', () {
    test('create adds document and returns ID', () async {
      final id = await repo.create(
        name: 'Bench Press',
        description: 'Flat bench',
        instructions: 'Lie on bench, press bar up',
        userId: 'user1',
      );

      expect(id, isNotEmpty);

      final doc = await fakeFirestore
          .collection('exerciseTemplates')
          .doc(id)
          .get();
      expect(doc.exists, true);
      expect(doc.data()!['name'], 'Bench Press');
      expect(doc.data()!['createdBy'], 'user1');
      expect(doc.data()!['updatedBy'], 'user1');
      expect(doc.data()!['deletedAt'], isNull);
    });

    test('create stores videoUrl when provided', () async {
      final id = await repo.create(
        name: 'Deadlift',
        description: 'Conventional deadlift',
        instructions: 'Hinge at hips',
        userId: 'user1',
        videoUrl: 'https://example.com/video',
      );

      final doc = await fakeFirestore
          .collection('exerciseTemplates')
          .doc(id)
          .get();
      expect(doc.data()!['videoUrl'], 'https://example.com/video');
    });

    test('getById returns template', () async {
      final id = await repo.create(
        name: 'Row',
        description: 'Barbell row',
        instructions: 'Pull bar to chest',
        userId: 'user1',
      );

      final template = await repo.getById(id);
      expect(template, isNotNull);
      expect(template!.name, 'Row');
      expect(template.id, id);
    });

    test('getById returns null for non-existent doc', () async {
      final template = await repo.getById('nonexistent');
      expect(template, isNull);
    });

    test('getById returns null for soft-deleted template', () async {
      final id = await repo.create(
        name: 'OHP',
        description: 'Overhead press',
        instructions: 'Press bar overhead',
        userId: 'user1',
      );

      await repo.softDelete(id, 'user1');
      final template = await repo.getById(id);
      expect(template, isNull);
    });

    test('getByIdIncludingDeleted returns soft-deleted template', () async {
      final id = await repo.create(
        name: 'Archived Exercise',
        description: 'Was deleted',
        instructions: 'Still readable',
        userId: 'user1',
      );

      await repo.softDelete(id, 'user1');
      final template = await repo.getByIdIncludingDeleted(id);
      expect(template, isNotNull);
      expect(template!.name, 'Archived Exercise');
      expect(template.isDeleted, isTrue);
    });

    test('update modifies fields', () async {
      final id = await repo.create(
        name: 'Squat',
        description: 'Back squat',
        instructions: 'Squat down',
        userId: 'user1',
      );

      await repo.update(
        id: id,
        name: 'Front Squat',
        description: 'Front rack squat',
        instructions: 'Hold bar in front rack, squat down',
        userId: 'user1',
        videoUrl: 'https://example.com/front-squat',
      );

      final template = await repo.getById(id);
      expect(template!.name, 'Front Squat');
      expect(template.description, 'Front rack squat');
      expect(template.videoUrl, 'https://example.com/front-squat');
    });

    test('softDelete sets deletedAt and deletedBy', () async {
      final id = await repo.create(
        name: 'Curl',
        description: 'Bicep curl',
        instructions: 'Curl the bar',
        userId: 'user1',
      );

      await repo.softDelete(id, 'user1');

      // Read raw doc — soft-deleted should have deletedBy set
      final doc = await fakeFirestore
          .collection('exerciseTemplates')
          .doc(id)
          .get();
      expect(doc.data()!['deletedBy'], 'user1');
      expect(doc.data()!['deletedAt'], isNotNull);
    });

    test('watchAll streams only non-deleted templates for user', () async {
      // Create templates for user1
      await repo.create(
        name: 'Exercise A',
        description: 'Desc A',
        instructions: 'Do A',
        userId: 'user1',
      );
      final idB = await repo.create(
        name: 'Exercise B',
        description: 'Desc B',
        instructions: 'Do B',
        userId: 'user1',
      );
      // Create template for different user
      await repo.create(
        name: 'Exercise C',
        description: 'Desc C',
        instructions: 'Do C',
        userId: 'user2',
      );

      // Soft-delete one of user1's templates
      await repo.softDelete(idB, 'user1');

      final templates = await repo.watchAll('user1').first;
      expect(templates.length, 1);
      expect(templates.first.name, 'Exercise A');
    });

    test('serialization round-trip preserves all fields', () async {
      final id = await repo.create(
        name: 'Plank',
        description: 'Core hold',
        instructions: 'Hold body straight',
        userId: 'user1',
        videoUrl: 'https://example.com/plank',
      );

      final template = await repo.getById(id);
      expect(template, isNotNull);
      expect(template!.id, id);
      expect(template.name, 'Plank');
      expect(template.description, 'Core hold');
      expect(template.instructions, 'Hold body straight');
      expect(template.videoUrl, 'https://example.com/plank');
      expect(template.createdBy, 'user1');
      expect(template.updatedBy, 'user1');
      expect(template.isDeleted, false);
    });
  });
}
