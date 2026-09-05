import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/library/data/library_folder_repository.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late WorkoutTemplateRepository repo;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    repo = WorkoutTemplateRepository(firestore: fakeFirestore);
    for (final id in ['ex1', 'ex2']) {
      final header = fakeFirestore.collection('exerciseTemplates').doc(id);
      await header.set({
        'ownerId': 'user1',
        'createdBy': 'user1',
        'currentVersion': 4,
      });
      for (final version in [1, 4]) {
        await header.collection('exerciseVersions').doc('$version').set({
          'versionNumber': version,
          'name': id,
        });
      }
    }
  });

  group('WorkoutTemplate.copyWith', () {
    test('returns copy with updated fields', () {
      final now = DateTime(2026, 1, 1);
      final template = WorkoutTemplate(
        id: 'wt1',
        ownerId: 'user1',
        name: 'Pull Day',
        workoutType: WorkoutType.pull,
        currentVersion: 1,
        createdAt: now,
        createdBy: 'user1',
        updatedAt: now,
        updatedBy: 'user1',
      );
      final updated = template.copyWith(
        name: 'Upper Pull',
        workoutType: WorkoutType.upper,
      );
      expect(updated.name, 'Upper Pull');
      expect(updated.workoutType, WorkoutType.upper);
      expect(updated.id, 'wt1');
      expect(updated.currentVersion, 1);
    });

    test('hasPublishedVersion reflects currentVersion', () {
      final now = DateTime(2026, 1, 1);
      final draft = WorkoutTemplate(
        id: 'wt1',
        ownerId: 'user1',
        name: 'Draft',
        workoutType: WorkoutType.fullBody,
        currentVersion: 0,
        createdAt: now,
        createdBy: 'user1',
        updatedAt: now,
        updatedBy: 'user1',
      );
      expect(draft.hasPublishedVersion, isFalse);

      final published = draft.copyWith(currentVersion: 1);
      expect(published.hasPublishedVersion, isTrue);
    });
  });

  group('ExercisePrescription.copyWith', () {
    test('returns copy with updated fields', () {
      final p = ExercisePrescription(
        exerciseId: 'ex1',
        exerciseVersion: 4,
        sortOrder: 0,
        mode: ExerciseMode.reps,
        exerciseName: 'Squat',
        sets: 3,
        reps: '8-12',
      );
      final updated = p.copyWith(sets: 5, reps: '5');
      expect(updated.sets, 5);
      expect(updated.reps, '5');
      expect(updated.exerciseName, 'Squat');
      expect(updated.exerciseId, 'ex1');
      expect(updated.exerciseVersion, 4);
    });
  });

  group('WorkoutTemplateRepository', () {
    test('create adds document with currentVersion 0', () async {
      final id = await repo.create(
        name: 'Push Day',
        workoutType: WorkoutType.push,
        userId: 'user1',
      );

      expect(id, isNotEmpty);
      final doc =
          await fakeFirestore.collection('workoutTemplates').doc(id).get();
      expect(doc.exists, true);
      expect(doc.data()!['name'], 'Push Day');
      expect(doc.data()!['workoutType'], 'push');
      expect(doc.data()!['currentVersion'], 0);
      expect(doc.data()!['createdBy'], 'user1');
      expect(doc.data()!['ownerId'], 'user1');
      expect(doc.data()!['tags'], isEmpty);
      expect(doc.data()!['folderId'], isNull);
      expect(doc.data()!['provenance'], isNull);
    });

    test('getById returns template', () async {
      final id = await repo.create(
        name: 'Leg Day',
        workoutType: WorkoutType.legs,
        userId: 'user1',
      );

      final template = await repo.getById(id);
      expect(template, isNotNull);
      expect(template!.name, 'Leg Day');
      expect(template.workoutType, WorkoutType.legs);
      expect(template.currentVersion, 0);
    });

    test('getById returns null for non-existent', () async {
      final template = await repo.getById('nonexistent');
      expect(template, isNull);
    });

    test('getById returns template created by a different user', () async {
      final id = await repo.create(
        name: 'Coach Workout',
        workoutType: WorkoutType.pull,
        userId: 'coach1',
      );

      // Any user can read — getById has no ownership filter
      final template = await repo.getById(id);
      expect(template, isNotNull);
      expect(template!.name, 'Coach Workout');
    });

    test('getById returns null for soft-deleted', () async {
      final id = await repo.create(
        name: 'To Delete',
        workoutType: WorkoutType.core,
        userId: 'user1',
      );
      await repo.softDelete(id, 'user1');
      final template = await repo.getById(id);
      expect(template, isNull);
    });

    test('update modifies header fields', () async {
      final id = await repo.create(
        name: 'Day A',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      await repo.update(
        id: id,
        name: 'Upper Pull Day',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );

      final template = await repo.getById(id);
      expect(template!.name, 'Upper Pull Day');
      expect(template.workoutType, WorkoutType.pull);
    });

    test('softDelete sets deletedAt and deletedBy', () async {
      final id = await repo.create(
        name: 'Tempo',
        workoutType: WorkoutType.endurance,
        userId: 'user1',
      );

      await repo.softDelete(id, 'user1');

      final doc =
          await fakeFirestore.collection('workoutTemplates').doc(id).get();
      expect(doc.data()!['deletedBy'], 'user1');
      expect(doc.data()!['deletedAt'], isNotNull);
    });

    test('watchAll streams only non-deleted templates for user', () async {
      await repo.create(
        name: 'Workout A',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );
      final idB = await repo.create(
        name: 'Workout B',
        workoutType: WorkoutType.lower,
        userId: 'user1',
      );
      // Different user
      await repo.create(
        name: 'Workout C',
        workoutType: WorkoutType.core,
        userId: 'user2',
      );
      await repo.softDelete(idB, 'user1');

      final templates = await repo.watchAll('user1').first;
      expect(templates.length, 1);
      expect(templates.first.name, 'Workout A');
    });

    test('publishVersion creates version and increments header', () async {
      final id = await repo.create(
        name: 'Power Session',
        workoutType: WorkoutType.power,
        userId: 'user1',
      );

      final exercises = [
        ExercisePrescription(
          exerciseId: 'ex1',
          exerciseVersion: 4,
          sortOrder: 0,
          mode: ExerciseMode.reps,
          exerciseName: 'Campus Board',
          sets: 5,
          reps: '5',
        ),
        ExercisePrescription(
          exerciseId: 'ex2',
          sortOrder: 1,
          mode: ExerciseMode.time,
          exerciseName: 'Limit Bouldering',
          durationSeconds: 300,
        ),
      ];

      final versionNum = await repo.publishVersion(
        templateId: id,
        exercises: exercises,
        userId: 'user1',
      );

      expect(versionNum, 1);

      // Header should be updated
      final header = await repo.getById(id);
      expect(header!.currentVersion, 1);
      expect(header.hasPublishedVersion, isTrue);

      // Version doc should exist
      final version = await repo.getVersion(id, 1);
      expect(version, isNotNull);
      expect(version!.versionNumber, 1);
      expect(version.exercises.length, 2);
      expect(version.exercises[0].exerciseName, 'Campus Board');
      expect(version.exercises[1].exerciseName, 'Limit Bouldering');
    });

    test('typed blocks and stable slots round-trip through Firestore',
        () async {
      final id = await repo.create(
        name: 'Mixed Session',
        workoutType: WorkoutType.conditioning,
        userId: 'user1',
      );

      await repo.publishVersion(
        templateId: id,
        blocks: [
          TimedIntervalBlock(
            blockId: 'interval-block',
            sortOrder: 0,
            slots: [
              ExerciseSlot(
                slotId: 'bike-slot',
                exerciseId: 'ex1',
                exerciseVersion: 4,
                sortOrder: 0,
                mode: ExerciseMode.time,
                durationSeconds: 30,
              ),
            ],
            rounds: 10,
            workSeconds: 30,
            restSeconds: 60,
          ),
          ClimbingRouteBlock(
            blockId: 'route-block',
            sortOrder: 1,
            route: ExerciseSlot(
              slotId: 'route-slot',
              exerciseId: 'ex2',
              sortOrder: 0,
              mode: ExerciseMode.amrap,
            ),
            grade: 'V5',
            color: 'Purple',
            targetAttempts: 4,
          ),
        ],
        userId: 'user1',
      );

      final versionDoc = await fakeFirestore
          .collection('workoutTemplates')
          .doc(id)
          .collection('workoutTemplateVersions')
          .doc('1')
          .get();
      expect(versionDoc.data()!['storageFormat'], 'typedWorkoutBlocksV1');
      expect(versionDoc.data()!['blockCount'], 2);
      expect(versionDoc.data()!['slotCount'], 2);

      final version = await repo.getVersion(id, 1);
      expect(version!.blocks[0], isA<TimedIntervalBlock>());
      expect((version.blocks[0] as TimedIntervalBlock).rounds, 10);
      expect(version.blocks[1], isA<ClimbingRouteBlock>());
      expect((version.blocks[1] as ClimbingRouteBlock).grade, 'V5');
      expect(version.exerciseSlots.map((slot) => slot.slotId), [
        'bike-slot',
        'route-slot',
      ]);
      expect(version.exerciseSlots.first.exerciseVersion, 4);
    });

    test('publishing canonicalizes valid unsorted blocks and slots', () async {
      final id = await repo.create(
        name: 'Unsorted Circuit',
        workoutType: WorkoutType.conditioning,
        userId: 'user1',
      );

      await repo.publishVersion(
        templateId: id,
        blocks: [
          StandardExerciseBlock(
            blockId: 'second-block',
            sortOrder: 1,
            exercise: ExerciseSlot(
              slotId: 'second-slot',
              exerciseId: 'ex2',
              sortOrder: 0,
              mode: ExerciseMode.reps,
            ),
          ),
          CircuitBlock(
            blockId: 'first-block',
            sortOrder: 0,
            slots: [
              ExerciseSlot(
                slotId: 'circuit-second',
                exerciseId: 'ex2',
                sortOrder: 1,
                mode: ExerciseMode.reps,
              ),
              ExerciseSlot(
                slotId: 'circuit-first',
                exerciseId: 'ex1',
                sortOrder: 0,
                mode: ExerciseMode.reps,
              ),
            ],
            rounds: 3,
          ),
        ],
        userId: 'user1',
      );

      final version = await repo.getVersion(id, 1);
      expect(version!.blocks.map((block) => block.blockId), [
        'first-block',
        'second-block',
      ]);
      expect(version.exerciseSlots.map((slot) => slot.slotId), [
        'circuit-first',
        'circuit-second',
        'second-slot',
      ]);
      final versionRef = fakeFirestore
          .collection('workoutTemplates')
          .doc(id)
          .collection('workoutTemplateVersions')
          .doc('1');
      expect(
        (await versionRef.get()).data()!['slotIds'],
        ['circuit-first', 'circuit-second', 'second-slot'],
      );
      expect(
        (await versionRef.get()).data()!['slots'][0]['slotId'],
        'circuit-first',
      );
    });

    test('resumes and seals an interrupted matching typed draft', () async {
      final id = await repo.create(
        name: 'Resumable',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );
      final versionRef = fakeFirestore
          .collection('workoutTemplates')
          .doc(id)
          .collection('workoutTemplateVersions')
          .doc('1');
      final block = {
        'blockId': 'resume-block',
        'type': 'standardExercise',
        'sortOrder': 0,
        'slotIds': ['resume-slot'],
        'slotStartOrder': 0,
        'slotCount': 1,
        'title': null,
        'notes': null,
      };
      final slot = {
        'slotId': 'resume-slot',
        'blockId': 'resume-block',
        'blockSortOrder': 0,
        'slotOrder': 0,
        'exerciseId': 'ex1',
        'exerciseVersion': 1,
        'sortOrder': 0,
        'exerciseName': null,
        'prescription': {
          'mode': 'reps',
          'sets': 3,
          'reps': '10',
          'durationSeconds': null,
          'weight': null,
          'restSeconds': null,
          'notes': null,
        },
      };
      await versionRef.set({
        'versionNumber': 1,
        'publishedAt': DateTime(2026, 1, 1),
        'storageFormat': 'typedWorkoutBlocksV1',
        'publishState': 'draft',
        'ownerId': 'user1',
        'blockCount': 1,
        'slotCount': 1,
        'blockIds': ['resume-block'],
        'slotIds': ['resume-slot'],
        'blocks': [block],
        'slots': [slot],
        'childWorkouts': <Map<String, dynamic>>[],
      });
      await versionRef
          .collection('workoutBlocks')
          .doc('resume-block')
          .set(block);
      await versionRef.collection('exerciseSlots').doc('resume-slot').set(slot);

      final published = await repo.publishVersion(
        templateId: id,
        userId: 'user1',
        blocks: [
          StandardExerciseBlock(
            blockId: 'resume-block',
            sortOrder: 0,
            exercise: ExerciseSlot(
              slotId: 'resume-slot',
              exerciseId: 'ex1',
              exerciseVersion: 1,
              sortOrder: 0,
              mode: ExerciseMode.reps,
              sets: 3,
              reps: '10',
            ),
          ),
        ],
      );

      expect(published, 1);
      expect((await versionRef.get()).data()!['publishState'], 'published');
      expect(
        (await fakeFirestore.collection('workoutTemplates').doc(id).get())
            .data()!['currentVersion'],
        1,
      );
    });

    test('replaces an owned stale draft before publishing', () async {
      final id = await repo.create(
        name: 'Replace Draft',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );
      final versionRef = fakeFirestore
          .collection('workoutTemplates')
          .doc(id)
          .collection('workoutTemplateVersions')
          .doc('1');
      await versionRef.set({
        'versionNumber': 1,
        'storageFormat': 'typedWorkoutBlocksV1',
        'publishState': 'draft',
        'ownerId': 'user1',
        'blockCount': 0,
        'slotCount': 0,
        'blockIds': <String>[],
        'slotIds': <String>[],
        'blocks': <Map<String, dynamic>>[],
        'slots': <Map<String, dynamic>>[],
      });

      await repo.publishVersion(
        templateId: id,
        userId: 'user1',
        blocks: [
          StandardExerciseBlock(
            blockId: 'replacement-block',
            sortOrder: 0,
            exercise: ExerciseSlot(
              slotId: 'replacement-slot',
              exerciseId: 'ex1',
              sortOrder: 0,
              mode: ExerciseMode.reps,
            ),
          ),
        ],
      );

      final data = (await versionRef.get()).data()!;
      expect(data['publishState'], 'published');
      expect(data['blockIds'], ['replacement-block']);
      expect(data['slotIds'], ['replacement-slot']);
    });

    test('legacy array prescriptions read as deterministic standard blocks',
        () async {
      await fakeFirestore.collection('workoutTemplates').doc('legacy').set({
        'ownerId': 'user1',
        'createdBy': 'user1',
        'currentVersion': 1,
      });
      await fakeFirestore
          .collection('workoutTemplates')
          .doc('legacy')
          .collection('workoutTemplateVersions')
          .doc('1')
          .set({
        'versionNumber': 1,
        'publishedAt': DateTime(2024, 1, 1),
        'exercises': [
          {
            'exerciseId': 'ex1',
            'sortOrder': 5,
            'mode': 'reps',
            'sets': 3,
            'reps': '5',
          },
          {
            'exerciseId': 'ex1',
            'sortOrder': 7,
            'mode': 'amrap',
            'durationSeconds': 60,
          },
        ],
      });

      final version = await repo.getVersion('legacy', 1);

      expect(version!.blocks, everyElement(isA<StandardExerciseBlock>()));
      expect(version.exerciseSlots.map((slot) => slot.slotId), [
        'legacy-slot-0',
        'legacy-slot-1',
      ]);
      expect(version.exerciseSlots.map((slot) => slot.exerciseId), [
        'ex1',
        'ex1',
      ]);
      expect(
        version.exerciseSlots.map((slot) => slot.legacyStorageOrder),
        [0, 1],
      );
    });

    test('legacy prescription gaps preserve storage order for completion',
        () async {
      final versionRef = fakeFirestore
          .collection('workoutTemplates')
          .doc('legacy-subcollection')
          .collection('workoutTemplateVersions')
          .doc('1');
      await fakeFirestore
          .collection('workoutTemplates')
          .doc('legacy-subcollection')
          .set({
        'ownerId': 'user1',
        'createdBy': 'user1',
        'currentVersion': 1,
      });
      await versionRef.set({
        'versionNumber': 1,
        'storageFormat': 'exercisePrescriptionSubcollection',
        'prescriptionCount': 2,
      });
      await versionRef.collection('exercisePrescriptions').doc('5').set({
        'exerciseId': 'ex1',
        'sortOrder': 5,
        'prescription': {'mode': 'reps'},
      });
      await versionRef.collection('exercisePrescriptions').doc('7').set({
        'exerciseId': 'ex2',
        'sortOrder': 7,
        'prescription': {'mode': 'time'},
      });

      final version = await repo.getVersion('legacy-subcollection', 1);

      expect(version!.exerciseSlots.map((slot) => slot.slotId), [
        'legacy-slot-5',
        'legacy-slot-7',
      ]);
      expect(
        version.exerciseSlots.map((slot) => slot.legacyStorageOrder),
        [5, 7],
      );
    });

    test('updates owner-scoped organization without publishing', () async {
      final folders = LibraryFolderRepository(
        firestore: fakeFirestore,
        itemType: LibraryItemType.workout,
      );
      final folderId = await folders.create(name: 'Power', userId: 'user1');
      final id = await repo.create(
        name: 'Power Session',
        workoutType: WorkoutType.power,
        userId: 'user1',
      );

      await repo.updateOrganization(
        id: id,
        tags: const [' Power ', 'Climbing', 'power'],
        folderId: folderId,
        userId: 'user1',
      );

      final workout = await repo.getById(id);
      expect(workout!.tags, ['Power', 'Climbing']);
      expect(workout.folderId, folderId);
      expect(workout.currentVersion, 0);
    });

    test('publishVersion increments from existing version', () async {
      final id = await repo.create(
        name: 'Evolving Workout',
        workoutType: WorkoutType.fullBody,
        userId: 'user1',
      );

      final v1 = await repo.publishVersion(
        templateId: id,
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
          ),
        ],
        userId: 'user1',
      );
      expect(v1, 1);

      final v2 = await repo.publishVersion(
        templateId: id,
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
          ),
          ExercisePrescription(
            exerciseId: 'ex2',
            sortOrder: 1,
            mode: ExerciseMode.time,
            durationSeconds: 60,
          ),
        ],
        userId: 'user1',
      );
      expect(v2, 2);

      final header = await repo.getById(id);
      expect(header!.currentVersion, 2);

      // Both versions should exist
      final version1 = await repo.getVersion(id, 1);
      expect(version1!.exercises.length, 1);
      final version2 = await repo.getVersion(id, 2);
      expect(version2!.exercises.length, 2);
    });

    test('getVersion returns null for non-existent version', () async {
      final id = await repo.create(
        name: 'No Versions',
        workoutType: WorkoutType.skill,
        userId: 'user1',
      );

      final version = await repo.getVersion(id, 1);
      expect(version, isNull);
    });

    test('publishVersion rejects missing and foreign exercise versions',
        () async {
      final id = await repo.create(
        name: 'Invalid references',
        workoutType: WorkoutType.skill,
        userId: 'user1',
      );

      expect(
        () => repo.publishVersion(
          templateId: id,
          exercises: [
            ExercisePrescription(
              exerciseId: 'missing',
              sortOrder: 0,
              mode: ExerciseMode.reps,
            ),
          ],
          userId: 'user1',
        ),
        throwsStateError,
      );
      await fakeFirestore.collection('exerciseTemplates').doc('foreign').set({
        'ownerId': 'user2',
        'createdBy': 'user2',
        'currentVersion': 1,
      });
      expect(
        () => repo.publishVersion(
          templateId: id,
          exercises: [
            ExercisePrescription(
              exerciseId: 'foreign',
              sortOrder: 0,
              mode: ExerciseMode.reps,
            ),
          ],
          userId: 'user1',
        ),
        throwsStateError,
      );
    });

    test('publishVersion rejects duplicate sort orders before writing',
        () async {
      final id = await repo.create(
        name: 'Duplicate slots',
        workoutType: WorkoutType.skill,
        userId: 'user1',
      );

      expect(
        () => repo.publishVersion(
          templateId: id,
          exercises: [
            ExercisePrescription(
              exerciseId: 'ex1',
              sortOrder: 0,
              mode: ExerciseMode.reps,
            ),
            ExercisePrescription(
              exerciseId: 'ex2',
              sortOrder: 0,
              mode: ExerciseMode.reps,
            ),
          ],
          userId: 'user1',
        ),
        throwsArgumentError,
      );
      expect((await repo.getById(id))!.currentVersion, 0);
      expect(await repo.getVersion(id, 1), isNull);
    });

    test('prescription serialization round-trip preserves all fields',
        () async {
      final id = await repo.create(
        name: 'Full Prescription Test',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      await repo.publishVersion(
        templateId: id,
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            exerciseVersion: 4,
            sortOrder: 0,
            mode: ExerciseMode.reps,
            exerciseName: 'Bench Press',
            sets: 4,
            reps: '6-8',
            weight: '185 lb',
            restSeconds: 120,
            notes: 'Pause at bottom',
          ),
        ],
        userId: 'user1',
      );

      final version = await repo.getVersion(id, 1);
      final p = version!.exercises.first;
      expect(p.exerciseId, 'ex1');
      expect(p.exerciseVersion, 4);
      expect(p.exerciseName, 'Bench Press');
      expect(p.mode, ExerciseMode.reps);
      expect(p.sets, 4);
      expect(p.reps, '6-8');
      expect(p.weight, '185 lb');
      expect(p.restSeconds, 120);
      expect(p.notes, 'Pause at bottom');
    });
  });

  group('WorkoutTemplateRepository ownership', () {
    test('reads legacy createdBy as ownerId', () async {
      await fakeFirestore.collection('workoutTemplates').doc('legacy').set({
        'name': 'Legacy',
        'workoutType': 'fullBody',
        'currentVersion': 0,
        'createdBy': 'user1',
      });

      final template = await repo.getById('legacy');

      expect(template!.ownerId, 'user1');
      expect(template.tags, isEmpty);
      expect(template.folderId, isNull);
      expect(template.provenance, isNull);
    });

    test('update throws when caller is not creator', () async {
      final id = await repo.create(
        name: 'Owned Workout',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );

      expect(
        () => repo.update(
          id: id,
          name: 'Hijacked',
          workoutType: WorkoutType.pull,
          userId: 'not_the_creator',
        ),
        throwsStateError,
      );
    });

    test('softDelete throws when caller is not creator', () async {
      final id = await repo.create(
        name: 'Owned Workout',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );

      expect(
        () => repo.softDelete(id, 'not_the_creator'),
        throwsStateError,
      );
    });

    test('publishVersion throws when caller is not creator', () async {
      final id = await repo.create(
        name: 'Owned Workout',
        workoutType: WorkoutType.pull,
        userId: 'user1',
      );

      expect(
        () => repo.publishVersion(
          templateId: id,
          exercises: [],
          userId: 'not_the_creator',
        ),
        throwsStateError,
      );
    });
  });

  group('WorkoutTemplateRepository duplicate', () {
    test('duplicateTemplate creates new template with copied name', () async {
      final sourceId = await repo.create(
        name: 'Push Day',
        workoutType: WorkoutType.push,
        userId: 'user1',
      );

      final copyId = await repo.duplicateTemplate(
        sourceTemplateId: sourceId,
        userId: 'user1',
      );

      expect(copyId, isNot(sourceId));

      final copy = await repo.getById(copyId);
      expect(copy, isNotNull);
      expect(copy!.name, 'Push Day (Copy)');
      expect(copy.workoutType, WorkoutType.push);
      expect(copy.currentVersion, 0);
      expect(copy.hasPublishedVersion, isFalse);
      expect(copy.provenance!.sourceTemplateId, sourceId);
      expect(copy.provenance!.sourceOwnerId, 'user1');
      expect(copy.provenance!.sourceVersion, 0);
      expect(copy.provenance!.copiedBy, 'user1');
    });

    test('duplicateTemplate throws for non-existent source', () async {
      expect(
        () => repo.duplicateTemplate(
          sourceTemplateId: 'nonexistent',
          userId: 'user1',
        ),
        throwsStateError,
      );
    });

    test('getLatestExercises returns exercises from latest version', () async {
      final id = await repo.create(
        name: 'Exercises Test',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      await repo.publishVersion(
        templateId: id,
        exercises: [
          ExercisePrescription(
            exerciseId: 'ex1',
            sortOrder: 0,
            mode: ExerciseMode.reps,
            exerciseName: 'Bench Press',
            sets: 3,
            reps: '8-12',
          ),
        ],
        userId: 'user1',
      );

      final exercises = await repo.getLatestExercises(id);
      expect(exercises.length, 1);
      expect(exercises[0].exerciseName, 'Bench Press');
    });

    test('getLatestExercises returns empty for unpublished template', () async {
      final id = await repo.create(
        name: 'No Version',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      final exercises = await repo.getLatestExercises(id);
      expect(exercises, isEmpty);
    });
  });

  group('WorkoutTemplateRepository.isWorkoutReferenced', () {
    test('returns true when workout is in a published program', () async {
      final workoutId = await repo.create(
        name: 'Referenced Workout',
        workoutType: WorkoutType.upper,
        userId: 'user1',
      );

      // Create a program that references this workout
      final programRef = fakeFirestore.collection('programs').doc();
      await programRef.set({
        'name': 'My Program',
        'currentVersion': 1,
        'deletedAt': null,
        'ownerId': 'user1',
      });
      await programRef.collection('programVersions').doc('1').set({
        'versionNumber': 1,
        'entries': [
          {
            'workoutTemplateId': workoutId,
            'workoutTemplateVersion': 1,
            'dayOffset': 0,
            'sortOrder': 0
          },
        ],
      });

      final referenced = await repo.isWorkoutReferenced(workoutId);
      expect(referenced, isTrue);
    });

    test('returns false when workout is not referenced', () async {
      final workoutId = await repo.create(
        name: 'Unreferenced Workout',
        workoutType: WorkoutType.lower,
        userId: 'user1',
      );

      final referenced = await repo.isWorkoutReferenced(workoutId);
      expect(referenced, isFalse);
    });

    test('returns false when referencing program is deleted', () async {
      final workoutId = await repo.create(
        name: 'Freed Workout',
        workoutType: WorkoutType.fullBody,
        userId: 'user1',
      );

      final programRef = fakeFirestore.collection('programs').doc();
      await programRef.set({
        'name': 'Deleted Program',
        'currentVersion': 1,
        'deletedAt': Timestamp.now(),
        'ownerId': 'user1',
      });
      await programRef.collection('programVersions').doc('1').set({
        'versionNumber': 1,
        'entries': [
          {
            'workoutTemplateId': workoutId,
            'workoutTemplateVersion': 1,
            'dayOffset': 0,
            'sortOrder': 0
          },
        ],
      });

      final referenced = await repo.isWorkoutReferenced(workoutId);
      expect(referenced, isFalse);
    });
  });
}
