import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/programs/data/program_folder_repository.dart';
import 'package:stage4/features/programs/data/program_repository.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late ProgramFolderRepository repo;
  late ProgramRepository programRepo;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repo = ProgramFolderRepository(firestore: fakeFirestore);
    programRepo = ProgramRepository(firestore: fakeFirestore);
  });

  group('ProgramFolderRepository', () {
    test('create returns id and stores owner-scoped folder', () async {
      final id = await repo.create(name: 'Strength', userId: 'coach1');
      expect(id, isNotEmpty);

      final doc =
          await fakeFirestore.collection('programFolders').doc(id).get();
      expect(doc.data()!['name'], 'Strength');
      expect(doc.data()!['ownerId'], 'coach1');
    });

    test('create trims the name and rejects blank names', () async {
      final id = await repo.create(name: '  Hypertrophy  ', userId: 'coach1');
      final doc =
          await fakeFirestore.collection('programFolders').doc(id).get();
      expect(doc.data()!['name'], 'Hypertrophy');

      expect(
        () => repo.create(name: '   ', userId: 'coach1'),
        throwsArgumentError,
      );
    });

    test('watchFolders streams only the caller folders, sorted by name',
        () async {
      await repo.create(name: 'Beta', userId: 'coach1');
      await repo.create(name: 'Alpha', userId: 'coach1');
      await repo.create(name: 'Other', userId: 'coach2');

      final folders = await repo.watchFolders('coach1').first;
      expect(folders.map((f) => f.name).toList(), ['Alpha', 'Beta']);
    });

    test('rename updates the name', () async {
      final id = await repo.create(name: 'Old', userId: 'coach1');
      await repo.rename(folderId: id, name: 'New', userId: 'coach1');

      final doc =
          await fakeFirestore.collection('programFolders').doc(id).get();
      expect(doc.data()!['name'], 'New');
    });

    test('rename throws when caller is not the owner', () async {
      final id = await repo.create(name: 'Old', userId: 'coach1');
      expect(
        () => repo.rename(folderId: id, name: 'New', userId: 'intruder'),
        throwsStateError,
      );
    });

    test('delete removes the folder and clears member folderIds', () async {
      final folderId = await repo.create(name: 'Block', userId: 'coach1');
      final programId = await programRepo.create(
        name: 'Member',
        type: ProgramType.assignable,
        userId: 'coach1',
      );
      await programRepo.setFolder(
        id: programId,
        folderId: folderId,
        userId: 'coach1',
      );

      await repo.delete(folderId: folderId, userId: 'coach1');

      final folderDoc =
          await fakeFirestore.collection('programFolders').doc(folderId).get();
      expect(folderDoc.exists, isFalse);

      final program = await programRepo.getById(programId);
      expect(program!.folderId, isNull);
    });

    test('delete throws when caller is not the owner', () async {
      final id = await repo.create(name: 'Block', userId: 'coach1');
      expect(
        () => repo.delete(folderId: id, userId: 'intruder'),
        throwsStateError,
      );
    });
  });
}
