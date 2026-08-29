import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/features/library/data/library_folder_repository.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/programs/domain/program.dart';

/// Firestore repository for owner-scoped program folders.
///
/// Targets the top-level `programFolders` collection. Folders are flat
/// (no nesting) and used to organize a trainer's programs. A program
/// references at most one folder via its `folderId` field.
class ProgramFolderRepository {
  ProgramFolderRepository({
    FirebaseFirestore? firestore,
  }) : _delegate = LibraryFolderRepository(
          firestore: firestore,
          itemType: LibraryItemType.program,
        );

  final LibraryFolderRepository _delegate;

  /// Verifies the caller owns the folder. Throws [StateError] if not.
  Future<void> verifyOwnership(String folderId, String userId) =>
      _delegate.verifyOwnership(folderId, userId);

  /// Streams the caller's folders, ordered alphabetically by name.
  Stream<List<ProgramFolder>> watchFolders(String userId) =>
      _delegate.watchFolders(userId);

  /// Creates a new folder owned by [userId]. Returns the new document ID.
  Future<String> create({
    required String name,
    required String userId,
  }) =>
      _delegate.create(name: name, userId: userId);

  /// Renames a folder. Throws [StateError] if the caller is not the owner.
  Future<void> rename({
    required String folderId,
    required String name,
    required String userId,
  }) =>
      _delegate.rename(folderId: folderId, name: name, userId: userId);

  /// Deletes a folder and clears `folderId` on any programs that
  /// referenced it (those programs become "Uncategorized").
  ///
  /// Throws [StateError] if the caller is not the owner.
  Future<void> delete({
    required String folderId,
    required String userId,
  }) =>
      _delegate.delete(folderId: folderId, userId: userId);
}
