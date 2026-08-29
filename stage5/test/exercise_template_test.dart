import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/exercises/data/exercise_template_repository.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ExerciseTemplateRepository repository;

  const measurement = ExerciseMeasurementConfiguration(
    primary: ExerciseMeasurementType.weight,
    secondary: [ExerciseMeasurementType.repetitions],
  );
  const grading = ExerciseGradingConfiguration(
    system: ExerciseGradingSystem.gymColor,
    gymColors: ['Yellow', 'Blue', 'Black'],
  );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = ExerciseTemplateRepository(firestore: firestore);
  });

  ExerciseVersion version({
    int number = 1,
    String name = 'Back Squat',
  }) {
    return ExerciseVersion(
      versionNumber: number,
      name: name,
      description: 'Barbell squat',
      instructions: 'Brace and squat',
      videoUrl: 'https://example.com/squat',
      mediaUrls: const ['https://example.com/squat.jpg'],
      exerciseType: ExerciseType.strength,
      measurementConfiguration: measurement,
      gradingConfiguration: grading,
      publishedAt: DateTime(2026, 1, 1),
      publishedBy: 'coach1',
    );
  }

  group('exercise version domain', () {
    test('validates complete execution configuration', () {
      expect(() => version().validate(), returnsNormally);
    });

    test('rejects invalid version numbers', () {
      expect(() => version(number: 0).validate(), throwsArgumentError);
    });

    test('rejects duplicate primary and secondary measurements', () {
      final invalid = version().copyWithMeasurement(
        const ExerciseMeasurementConfiguration(
          primary: ExerciseMeasurementType.weight,
          secondary: [ExerciseMeasurementType.weight],
        ),
      );
      expect(() => invalid.validate(), throwsArgumentError);
    });

    test('gym color grading requires configured colors', () {
      const invalid = ExerciseGradingConfiguration(
        system: ExerciseGradingSystem.gymColor,
      );
      expect(() => invalid.validate(), throwsArgumentError);
    });

    test('logical header exposes current immutable version', () {
      final exercise = ExerciseTemplate(
        id: 'exercise1',
        ownerId: 'coach1',
        currentVersion: 1,
        version: version(),
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2026, 1, 1),
        updatedBy: 'coach1',
      );

      exercise.validate();
      expect(exercise.name, 'Back Squat');
      expect(exercise.measurementConfiguration, measurement);
      expect(exercise.currentVersion, 1);
      expect(exercise.isDeleted, isFalse);
    });

    test('logical header can resolve an older historical version', () {
      final exercise = ExerciseTemplate(
        id: 'exercise1',
        ownerId: 'coach1',
        currentVersion: 2,
        version: version(),
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2026, 1, 1),
        updatedBy: 'coach1',
      );
      expect(() => exercise.validate(), returnsNormally);
      expect(exercise.version.versionNumber, 1);
    });
  });

  group('ExerciseTemplateRepository versioning', () {
    test('create atomically writes a stable header and immutable version 1',
        () async {
      final id = await repository.create(
        name: 'Moon Board',
        description: 'Board climbing',
        instructions: 'Climb the selected problem',
        videoUrl: 'https://example.com/moon-board',
        mediaUrls: const ['https://example.com/problem.png'],
        exerciseType: ExerciseType.climbing,
        measurementConfiguration: const ExerciseMeasurementConfiguration(
          primary: ExerciseMeasurementType.completion,
        ),
        gradingConfiguration: const ExerciseGradingConfiguration(
          system: ExerciseGradingSystem.vScale,
        ),
        userId: 'coach1',
      );

      final header =
          await firestore.collection('exerciseTemplates').doc(id).get();
      expect(header.data()!['ownerId'], 'coach1');
      expect(header.data()!['currentVersion'], 1);
      expect(header.data()!.containsKey('name'), isFalse);

      final rawVersion =
          await header.reference.collection('exerciseVersions').doc('1').get();
      expect(rawVersion.data()!['name'], 'Moon Board');
      expect(rawVersion.data()!['exerciseType'], 'climbing');
      expect(
        rawVersion.data()!['measurementConfiguration']['primary'],
        'completion',
      );
      expect(rawVersion.data()!['gradingConfiguration']['system'], 'vScale');

      final exercise = await repository.getById(id);
      expect(exercise!.name, 'Moon Board');
      expect(exercise.currentVersion, 1);
      expect(exercise.version.mediaUrls, ['https://example.com/problem.png']);
    });

    test('update publishes v2 without changing v1', () async {
      final id = await repository.create(
        name: 'Squat',
        description: 'Back squat',
        instructions: 'Squat down',
        exerciseType: ExerciseType.strength,
        measurementConfiguration: measurement,
        gradingConfiguration: grading,
        userId: 'coach1',
      );

      final nextVersion = await repository.update(
        id: id,
        name: 'Front Squat',
        description: 'Front rack squat',
        instructions: 'Keep elbows high',
        videoUrl: 'https://example.com/front-squat',
        userId: 'coach1',
      );

      expect(nextVersion, 2);
      final v1 = await repository.getVersion(id, 1);
      final v2 = await repository.getVersion(id, 2);
      expect(v1!.name, 'Squat');
      expect(v2!.name, 'Front Squat');
      expect(
          v2.measurementConfiguration.primary, ExerciseMeasurementType.weight);
      expect(v2.gradingConfiguration!.gymColors, grading.gymColors);
      expect((await repository.getById(id))!.currentVersion, 2);
    });

    test('can resolve a historical version through the logical exercise',
        () async {
      final id = await repository.create(
        name: 'Original',
        description: 'Original description',
        instructions: 'Original instructions',
        userId: 'coach1',
      );
      await repository.update(
        id: id,
        name: 'Updated',
        description: 'Updated description',
        instructions: 'Updated instructions',
        userId: 'coach1',
      );

      final historical = await repository.getById(id, versionNumber: 1);
      expect(historical!.name, 'Original');
      expect(historical.currentVersion, 2);
      expect(historical.version.versionNumber, 1);
    });

    test('watchAll resolves latest versions and filters owner and deletion',
        () async {
      final first = await repository.create(
        name: 'First',
        description: 'Description',
        instructions: 'Instructions',
        userId: 'coach1',
      );
      await repository.create(
        name: 'Other owner',
        description: 'Description',
        instructions: 'Instructions',
        userId: 'coach2',
      );
      final deleted = await repository.create(
        name: 'Deleted',
        description: 'Description',
        instructions: 'Instructions',
        userId: 'coach1',
      );
      await repository.update(
        id: first,
        name: 'Latest First',
        description: 'Description',
        instructions: 'Instructions',
        userId: 'coach1',
      );
      await repository.softDelete(deleted, 'coach1');

      final exercises = await repository.watchAll('coach1').first;
      expect(exercises.map((exercise) => exercise.name), ['Latest First']);
    });

    test('soft-deleted exercise remains resolvable for historical workouts',
        () async {
      final id = await repository.create(
        name: 'Archived',
        description: 'Description',
        instructions: 'Instructions',
        userId: 'coach1',
      );
      await repository.softDelete(id, 'coach1');

      expect(await repository.getById(id), isNull);
      final archived = await repository.getByIdIncludingDeleted(id);
      expect(archived!.isDeleted, isTrue);
      expect(archived.name, 'Archived');
    });
  });

  group('legacy compatibility and backfill', () {
    Future<void> seedLegacy(String id, {String owner = 'coach1'}) async {
      await firestore.collection('exerciseTemplates').doc(id).set({
        'name': 'Legacy Squat',
        'description': 'Legacy description',
        'instructions': 'Legacy instructions',
        'videoUrl': 'https://example.com/legacy',
        'exerciseType': 'strength',
        'measurementConfiguration': {
          'primary': 'weight',
          'secondary': ['repetitions'],
        },
        'createdBy': owner,
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'updatedBy': owner,
        'deletedAt': null,
      });
    }

    test('legacy document is read as synthetic version 1', () async {
      await seedLegacy('legacy');

      final exercise = await repository.getById('legacy');
      expect(exercise!.ownerId, 'coach1');
      expect(exercise.currentVersion, 1);
      expect(exercise.version.versionNumber, 1);
      expect(exercise.name, 'Legacy Squat');
      expect(
        exercise.measurementConfiguration.primary,
        ExerciseMeasurementType.weight,
      );
    });

    test('explicit backfill materializes v1 and removes legacy payload',
        () async {
      await seedLegacy('legacy');

      final result = await repository.backfillLegacyVersion('legacy', 'coach1');
      expect(result, ExerciseBackfillResult.backfilled);

      final header =
          await firestore.collection('exerciseTemplates').doc('legacy').get();
      expect(header.data()!['ownerId'], 'coach1');
      expect(header.data()!['currentVersion'], 1);
      expect(header.data()!.containsKey('name'), isFalse);
      final v1 = await repository.getVersion('legacy', 1);
      expect(v1!.name, 'Legacy Squat');
      expect(v1.publishedAt, DateTime(2025, 1, 1));
    });

    test('backfill is idempotent', () async {
      await seedLegacy('legacy');
      await repository.backfillLegacyVersion('legacy', 'coach1');

      expect(
        await repository.backfillLegacyVersion('legacy', 'coach1'),
        ExerciseBackfillResult.notNeeded,
      );
    });

    test('first legacy edit preserves v1 and publishes v2', () async {
      await seedLegacy('legacy');

      final number = await repository.update(
        id: 'legacy',
        name: 'Edited Squat',
        description: 'New description',
        instructions: 'New instructions',
        userId: 'coach1',
      );

      expect(number, 2);
      expect((await repository.getVersion('legacy', 1))!.name, 'Legacy Squat');
      expect((await repository.getVersion('legacy', 2))!.name, 'Edited Squat');
    });

    test('owned batch backfill only counts legacy records', () async {
      await seedLegacy('legacy1');
      await seedLegacy('legacy2');
      await repository.create(
        name: 'Versioned',
        description: 'Description',
        instructions: 'Instructions',
        userId: 'coach1',
      );
      await seedLegacy('other', owner: 'coach2');

      expect(await repository.backfillOwnedLegacyExercises('coach1'), 2);
    });

    test('update and backfill reject non-owner', () async {
      await seedLegacy('legacy');

      expect(
        () => repository.update(
          id: 'legacy',
          name: 'Hijacked',
          description: 'Description',
          instructions: 'Instructions',
          userId: 'stranger',
        ),
        throwsStateError,
      );
      expect(
        () => repository.backfillLegacyVersion('legacy', 'stranger'),
        throwsStateError,
      );
    });
  });

  group('workout reference compatibility', () {
    test('finds references in immutable prescription subcollections', () async {
      final exerciseId = await repository.create(
        name: 'Pinned',
        description: 'Description',
        instructions: 'Instructions',
        userId: 'coach1',
      );
      final workout = firestore.collection('workoutTemplates').doc('workout');
      await workout.set({
        'ownerId': 'coach1',
        'createdBy': 'coach1',
        'currentVersion': 1,
        'deletedAt': null,
      });
      final version =
          workout.collection('workoutTemplateVersions').doc('1');
      await version.set({
        'versionNumber': 1,
        'storageFormat': 'exercisePrescriptionSubcollection',
      });
      await version.collection('exercisePrescriptions').doc('0').set({
        'exerciseId': exerciseId,
        'exerciseVersion': 1,
        'sortOrder': 0,
      });

      expect(await repository.isExerciseReferenced(exerciseId), isTrue);
    });

    test('continues finding references in legacy workout arrays', () async {
      final exerciseId = await repository.create(
        name: 'Legacy pinned',
        description: 'Description',
        instructions: 'Instructions',
        userId: 'coach1',
      );
      final workout = firestore.collection('workoutTemplates').doc('legacy');
      await workout.set({
        'ownerId': 'coach1',
        'createdBy': 'coach1',
        'currentVersion': 1,
        'deletedAt': null,
      });
      await workout.collection('workoutTemplateVersions').doc('1').set({
        'versionNumber': 1,
        'exercises': [
          {'exerciseId': exerciseId, 'sortOrder': 0},
        ],
      });

      expect(await repository.isExerciseReferenced(exerciseId), isTrue);
    });
  });
}

extension on ExerciseVersion {
  ExerciseVersion copyWithMeasurement(
    ExerciseMeasurementConfiguration configuration,
  ) {
    return ExerciseVersion(
      versionNumber: versionNumber,
      name: name,
      description: description,
      instructions: instructions,
      videoUrl: videoUrl,
      mediaUrls: mediaUrls,
      exerciseType: exerciseType,
      measurementConfiguration: configuration,
      gradingConfiguration: gradingConfiguration,
      publishedAt: publishedAt,
      publishedBy: publishedBy,
    );
  }
}
