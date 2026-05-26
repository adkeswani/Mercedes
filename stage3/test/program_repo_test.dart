import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage3/core/enums.dart';
import 'package:stage3/features/programs/data/program_repository.dart';
import 'package:stage3/features/programs/domain/program.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late ProgramRepository repo;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repo = ProgramRepository(firestore: fakeFirestore);
  });

  group('ProgramRepository', () {
    test('create returns doc ID and stores data', () async {
      final id = await repo.create(
        name: '8-Week Strength',
        type: ProgramType.assignable,
        userId: 'coach1',
        description: 'Progressive overload',
      );

      expect(id, isNotEmpty);

      final doc =
          await fakeFirestore.collection('programs').doc(id).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['name'], '8-Week Strength');
      expect(doc.data()!['description'], 'Progressive overload');
      expect(doc.data()!['ownerId'], 'coach1');
      expect(doc.data()!['type'], 'assignable');
      expect(doc.data()!['status'], 'draft');
      expect(doc.data()!['currentVersion'], 0);
    });

    test('getById returns program', () async {
      final id = await repo.create(
        name: 'My Program',
        type: ProgramType.personal,
        userId: 'athlete1',
      );

      final program = await repo.getById(id);
      expect(program, isNotNull);
      expect(program!.name, 'My Program');
      expect(program.type, ProgramType.personal);
      expect(program.ownerId, 'athlete1');
      expect(program.isDraft, isTrue);
    });

    test('getById returns null for soft-deleted program', () async {
      final id = await repo.create(
        name: 'Deleted Program',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      await repo.softDelete(id, 'coach1');

      final result = await repo.getById(id);
      expect(result, isNull);
    });

    test('update changes editable fields', () async {
      final id = await repo.create(
        name: 'Original',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      await repo.update(
        id: id,
        name: 'Updated Name',
        userId: 'coach1',
        description: 'New description',
      );

      final program = await repo.getById(id);
      expect(program!.name, 'Updated Name');
      expect(program.description, 'New description');
    });

    test('updateType changes program type', () async {
      final id = await repo.create(
        name: 'Type Test',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      await repo.updateType(
        id: id,
        type: ProgramType.personal,
        userId: 'coach1',
      );

      final program = await repo.getById(id);
      expect(program!.type, ProgramType.personal);
      expect(program.isAssignable, isFalse);
    });

    test('update throws when caller is not owner', () async {
      final id = await repo.create(
        name: 'Owned by coach1',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      expect(
        () => repo.update(
          id: id,
          name: 'Hijacked',
          userId: 'not_the_owner',
        ),
        throwsStateError,
      );
    });

    test('softDelete throws when caller is not owner', () async {
      final id = await repo.create(
        name: 'Owned by coach1',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      expect(
        () => repo.softDelete(id, 'not_the_owner'),
        throwsStateError,
      );
    });

    test('softDelete throws when athletes are enrolled', () async {
      final id = await repo.create(
        name: 'Has Athletes',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      // Create an active enrollment
      await fakeFirestore.collection('enrollments').doc('${id}_athlete1').set({
        'programId': id,
        'athleteId': 'athlete1',
        'status': 'active',
        'addedBy': 'coach1',
      });

      expect(
        () => repo.softDelete(id, 'coach1'),
        throwsStateError,
      );
    });

    test('softDelete succeeds when all enrollments are removed', () async {
      final id = await repo.create(
        name: 'Was Enrolled',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      // Create a removed enrollment (not active)
      await fakeFirestore.collection('enrollments').doc('${id}_athlete1').set({
        'programId': id,
        'athleteId': 'athlete1',
        'status': 'removed',
        'addedBy': 'coach1',
      });

      // Should succeed — no active enrollments
      await repo.softDelete(id, 'coach1');
      final result = await repo.getById(id);
      expect(result, isNull);
    });

    test('updateType throws when caller is not owner', () async {
      final id = await repo.create(
        name: 'Owned by coach1',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      expect(
        () => repo.updateType(
          id: id,
          type: ProgramType.personal,
          userId: 'not_the_owner',
        ),
        throwsStateError,
      );
    });

    test('watchAll streams programs for a user', () async {
      await repo.create(
        name: 'Program A',
        type: ProgramType.assignable,
        userId: 'coach1',
      );
      await repo.create(
        name: 'Program B',
        type: ProgramType.personal,
        userId: 'coach1',
      );
      await repo.create(
        name: 'Other Coach',
        type: ProgramType.assignable,
        userId: 'coach2',
      );

      final programs = await repo.watchAll('coach1').first;
      expect(programs.length, 2);
      expect(programs.map((p) => p.name), containsAll(['Program A', 'Program B']));
    });

    test('watchAll excludes soft-deleted programs', () async {
      final id = await repo.create(
        name: 'To Delete',
        type: ProgramType.assignable,
        userId: 'coach1',
      );
      await repo.softDelete(id, 'coach1');

      final programs = await repo.watchAll('coach1').first;
      expect(programs, isEmpty);
    });

    test('publishVersion creates version and updates header', () async {
      final id = await repo.create(
        name: 'Publish Test',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      final workouts = [
        ProgramWorkoutRef(
          workoutTemplateId: 'wt1',
          workoutTemplateVersion: 1,
          sortOrder: 0,
        ),
        ProgramWorkoutRef(
          workoutTemplateId: 'wt2',
          workoutTemplateVersion: 2,
          sortOrder: 1,
        ),
      ];

      final version = await repo.publishVersion(
        programId: id,
        workouts: workouts,
        userId: 'coach1',
        changeNote: 'Initial publish',
      );

      expect(version, 1);

      // Header should be updated
      final program = await repo.getById(id);
      expect(program!.currentVersion, 1);
      expect(program.status, ProgramStatus.published);

      // Version doc should exist
      final versionDoc = await repo.getVersion(id, 1);
      expect(versionDoc, isNotNull);
      expect(versionDoc!.versionNumber, 1);
      expect(versionDoc.workouts.length, 2);
      expect(versionDoc.changeNote, 'Initial publish');
      expect(versionDoc.workouts[0].workoutTemplateId, 'wt1');
      expect(versionDoc.workouts[1].workoutTemplateId, 'wt2');
    });

    test('publishVersion increments version number', () async {
      final id = await repo.create(
        name: 'Multi-Version',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      final v1 = await repo.publishVersion(
        programId: id,
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
        ],
        userId: 'coach1',
      );

      final v2 = await repo.publishVersion(
        programId: id,
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
          ProgramWorkoutRef(
            workoutTemplateId: 'wt2',
            workoutTemplateVersion: 1,
            sortOrder: 1,
          ),
        ],
        userId: 'coach1',
        changeNote: 'Added second workout',
      );

      expect(v1, 1);
      expect(v2, 2);

      final program = await repo.getById(id);
      expect(program!.currentVersion, 2);

      final version2 = await repo.getVersion(id, 2);
      expect(version2!.workouts.length, 2);
      expect(version2.changeNote, 'Added second workout');
    });

    test('getVersion returns null for non-existent version', () async {
      final id = await repo.create(
        name: 'No Versions',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      final version = await repo.getVersion(id, 1);
      expect(version, isNull);
    });

    test('watchVersions streams versions', () async {
      final id = await repo.create(
        name: 'Stream Test',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      await repo.publishVersion(
        programId: id,
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
        ],
        userId: 'coach1',
      );

      final versions = await repo.watchVersions(id).first;
      expect(versions.length, 1);
      expect(versions.first.versionNumber, 1);
    });

    test('copyProgram creates a new draft with copied name', () async {
      final sourceId = await repo.create(
        name: 'Original Program',
        type: ProgramType.assignable,
        userId: 'coach1',
        description: 'A great program',
      );

      await repo.publishVersion(
        programId: sourceId,
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
        ],
        userId: 'coach1',
      );

      final copyId = await repo.copyProgram(
        sourceProgramId: sourceId,
        userId: 'coach1',
      );

      expect(copyId, isNot(sourceId));

      final copy = await repo.getById(copyId);
      expect(copy, isNotNull);
      expect(copy!.name, 'Original Program (Copy)');
      expect(copy.description, 'A great program');
      expect(copy.type, ProgramType.assignable);
      expect(copy.isDraft, isTrue);
      expect(copy.currentVersion, 0);
    });

    test('publishVersion preserves workoutName', () async {
      final id = await repo.create(
        name: 'Name Test',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      await repo.publishVersion(
        programId: id,
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
            workoutName: 'Push Day',
          ),
          ProgramWorkoutRef(
            workoutTemplateId: 'wt2',
            workoutTemplateVersion: 2,
            sortOrder: 1,
            workoutName: 'Pull Day',
          ),
        ],
        userId: 'coach1',
      );

      final versionDoc = await repo.getVersion(id, 1);
      expect(versionDoc!.workouts[0].workoutName, 'Push Day');
      expect(versionDoc.workouts[1].workoutName, 'Pull Day');
    });

    test('publishVersion handles null workoutName', () async {
      final id = await repo.create(
        name: 'Null Name Test',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      await repo.publishVersion(
        programId: id,
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
        ],
        userId: 'coach1',
      );

      final versionDoc = await repo.getVersion(id, 1);
      expect(versionDoc!.workouts[0].workoutName, isNull);
    });

    test('copyProgram throws for non-existent source', () async {
      expect(
        () => repo.copyProgram(
          sourceProgramId: 'nonexistent',
          userId: 'coach1',
        ),
        throwsStateError,
      );
    });

    test('getLatestWorkoutRefs returns workouts from latest version',
        () async {
      final id = await repo.create(
        name: 'Refs Test',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      await repo.publishVersion(
        programId: id,
        workouts: [
          ProgramWorkoutRef(
            workoutTemplateId: 'wt1',
            workoutTemplateVersion: 1,
            sortOrder: 0,
          ),
          ProgramWorkoutRef(
            workoutTemplateId: 'wt2',
            workoutTemplateVersion: 2,
            sortOrder: 1,
          ),
        ],
        userId: 'coach1',
      );

      final refs = await repo.getLatestWorkoutRefs(id);
      expect(refs.length, 2);
      expect(refs[0].workoutTemplateId, 'wt1');
      expect(refs[1].workoutTemplateId, 'wt2');
    });

    test('getLatestWorkoutRefs returns empty for unpublished program',
        () async {
      final id = await repo.create(
        name: 'No Version',
        type: ProgramType.assignable,
        userId: 'coach1',
      );

      final refs = await repo.getLatestWorkoutRefs(id);
      expect(refs, isEmpty);
    });
  });

  group('Program.copyWith', () {
    test('copies all fields', () {
      final original = Program(
        id: 'p1',
        name: 'Original',
        description: 'Desc',
        ownerId: 'coach1',
        type: ProgramType.assignable,
        status: ProgramStatus.draft,
        currentVersion: 0,
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'coach1',
        updatedAt: DateTime(2024, 1, 2),
        updatedBy: 'coach1',
      );

      final copy = original.copyWith(name: 'Copied', currentVersion: 3);
      expect(copy.name, 'Copied');
      expect(copy.currentVersion, 3);
      expect(copy.id, 'p1');
      expect(copy.ownerId, 'coach1');
    });
  });
}
