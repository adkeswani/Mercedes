import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/library/data/library_collapse_preference.dart';
import 'package:stage5/features/library/data/library_folder_repository.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';

final libraryCollapsePreferenceProvider = Provider<LibraryCollapsePreference>((
  ref,
) {
  return createLibraryCollapsePreference();
});

final libraryFolderRepositoryProvider =
    Provider.family<LibraryFolderRepository, LibraryItemType>((ref, itemType) {
  return LibraryFolderRepository(itemType: itemType);
});

final libraryFoldersProvider =
    StreamProvider.family<List<LibraryFolder>, LibraryItemType>((
  ref,
  itemType,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .watch(libraryFolderRepositoryProvider(itemType))
      .watchFolders(user.uid);
});

String libraryCollapsePreferenceKey({
  required String userId,
  required LibraryItemType itemType,
  required String scopeId,
  required String? folderId,
}) {
  return '$userId.${itemType.name}.$scopeId.${folderId ?? 'unfiled'}';
}
