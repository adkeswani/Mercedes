import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/library/data/library_folder_repository.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';

void main() {
  group('library metadata domain', () {
    test('normalizes tags while preserving first display spelling', () {
      expect(
        normalizeLibraryTags([' Strength ', 'Power', 'strength']),
        ['Strength', 'Power'],
      );
    });

    test('rejects blank, oversized, and excessive tags', () {
      expect(() => normalizeLibraryTags(['  ']), throwsArgumentError);
      expect(
        () => normalizeLibraryTags([
          List.filled(maxLibraryTagLength + 1, 'x').join(),
        ]),
        throwsArgumentError,
      );
      expect(
        () => normalizeLibraryTags(
          List.generate(maxLibraryTags + 1, (index) => 'tag$index'),
        ),
        throwsArgumentError,
      );
    });

    test('validates immutable provenance', () {
      final provenance = TemplateProvenance(
        sourceTemplateId: 'source',
        sourceOwnerId: 'coach',
        sourceVersion: 2,
        copiedAt: DateTime(2026, 1, 1),
        copiedBy: 'coach',
      );
      expect(provenance.validate, returnsNormally);
      expect(
        () => TemplateProvenance(
          sourceTemplateId: 'source',
          sourceOwnerId: 'coach',
          sourceVersion: -1,
          copiedAt: DateTime(2026, 1, 1),
          copiedBy: 'coach',
        ).validate(),
        throwsArgumentError,
      );
    });

    test('resolves copy content from immutable provenance', () {
      final source = resolveLibraryEditorSource(
        targetTemplateId: 'copy',
        targetVersion: 0,
        routeSourceTemplateId: 'stale-route-id',
        provenance: TemplateProvenance(
          sourceTemplateId: 'pinned-source',
          sourceOwnerId: 'coach',
          sourceVersion: 2,
          copiedAt: DateTime(2026, 1, 1),
          copiedBy: 'coach',
        ),
      );
      expect(source.templateId, 'pinned-source');
      expect(source.version, 2);
    });

    test('legacy copies request the routed live source version', () {
      final source = resolveLibraryEditorSource(
        targetTemplateId: 'copy',
        targetVersion: 0,
        routeSourceTemplateId: 'legacy-source',
        provenance: null,
      );
      expect(source.templateId, 'legacy-source');
      expect(source.version, isNull);
    });

    test('published copies ignore stale copy routes', () {
      final source = resolveLibraryEditorSource(
        targetTemplateId: 'published-copy',
        targetVersion: 3,
        routeSourceTemplateId: 'original',
        provenance: TemplateProvenance(
          sourceTemplateId: 'original',
          sourceOwnerId: 'coach',
          sourceVersion: 1,
          copiedAt: DateTime(2026, 1, 1),
          copiedBy: 'coach',
        ),
      );
      expect(source.templateId, 'published-copy');
      expect(source.version, 3);
    });
  });

  group('LibraryFolderRepository', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('scopes shared folder storage by template type', () async {
      final exercises = LibraryFolderRepository(
        firestore: firestore,
        itemType: LibraryItemType.exercise,
      );
      final workouts = LibraryFolderRepository(
        firestore: firestore,
        itemType: LibraryItemType.workout,
      );
      await exercises.create(name: 'Climbing', userId: 'coach');
      await workouts.create(name: 'Sessions', userId: 'coach');

      expect(
        (await exercises.watchFolders('coach').first).map((f) => f.name),
        ['Climbing'],
      );
      expect(
        (await workouts.watchFolders('coach').first).map((f) => f.name),
        ['Sessions'],
      );
    });

    test('treats legacy untyped folders as program folders', () async {
      await firestore.collection('programFolders').doc('legacy').set({
        'ownerId': 'coach',
        'name': 'Legacy Programs',
        'createdBy': 'coach',
      });
      final programs = LibraryFolderRepository(
        firestore: firestore,
        itemType: LibraryItemType.program,
      );
      final exercises = LibraryFolderRepository(
        firestore: firestore,
        itemType: LibraryItemType.exercise,
      );

      expect(await programs.watchFolders('coach').first, hasLength(1));
      expect(await exercises.watchFolders('coach').first, isEmpty);
    });

    test('keeps interrupted deletion tombstones visible for retry', () async {
      final programs = LibraryFolderRepository(
        firestore: firestore,
        itemType: LibraryItemType.program,
      );
      final folderId =
          await programs.create(name: 'Retry deletion', userId: 'coach');
      await firestore.collection('programFolders').doc(folderId).update({
        'deletedAt': DateTime(2026, 1, 1),
        'deletedBy': 'coach',
      });

      final folders = await programs.watchFolders('coach').first;
      expect(folders.single.id, folderId);
      expect(folders.single.deletedAt, isNotNull);
    });

    test('delete only clears members of the matching template type', () async {
      final folders = LibraryFolderRepository(
        firestore: firestore,
        itemType: LibraryItemType.exercise,
      );
      final folderId = await folders.create(name: 'Board', userId: 'coach');
      await firestore.collection('exerciseTemplates').doc('exercise').set({
        'ownerId': 'coach',
        'folderId': folderId,
      });
      await firestore.collection('workoutTemplates').doc('workout').set({
        'ownerId': 'coach',
        'folderId': folderId,
      });

      await folders.delete(folderId: folderId, userId: 'coach');

      expect(
        (await firestore.collection('exerciseTemplates').doc('exercise').get())
            .data()!['folderId'],
        isNull,
      );
      expect(
        (await firestore.collection('workoutTemplates').doc('workout').get())
            .data()!['folderId'],
        folderId,
      );
    });
  });
}
