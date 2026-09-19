import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_organizer.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';

/// Displays the user's program library.
class ProgramListScreen extends ConsumerWidget {
  const ProgramListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programsAsync = ref.watch(programsProvider);
    final foldersAsync = ref.watch(programFoldersProvider);
    final clientNames =
        ref.watch(activeTrainerClientNamesProvider).valueOrNull ?? const {};
    final userId = ref.watch(authStateProvider).valueOrNull?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Programs')),
      body: programsAsync.when(
        data: (programs) {
          if (programs.isEmpty) {
            if (browserAutomationEnabled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                markBrowserSmokeSurfaceFailure('trainer-programs', 'empty');
              });
            }
          }
          if (userId == null) {
            return const Center(child: Text('Sign in to view your library.'));
          }
          return foldersAsync.when(
            data: (folders) {
              final scopedClientIds = programs
                  .map((program) => program.clientAthleteId)
                  .whereType<String>();
              if (browserAutomationEnabled &&
                  programs.isNotEmpty &&
                  scopedClientIds.every(clientNames.containsKey)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  markBrowserSmokeSurfaceReady(
                    'trainer-programs',
                    content: [
                      programs.first.name,
                      ...programs.first.tags,
                      ...folders.map((folder) => folder.name),
                      'Clients',
                      'Unfiled',
                    ].join(' | '),
                  );
                });
              }
              return LibraryOrganizer<Program>(
                userId: userId,
                itemType: LibraryItemType.program,
                items: programs,
                folders: folders,
                emptyMessage: 'No programs yet. Tap + to create one.',
                nameOf: (item) => item.name,
                tagsOf: (item) => item.tags,
                folderIdOf: (item) => item.folderId,
                clientAthleteIdOf: (item) => item.clientAthleteId,
                activeClientNames: clientNames,
                supportsClientScope: true,
                tileBuilder: (context, item, organizationButton) =>
                    _ProgramTile(
                  program: item,
                  organizationButton: organizationButton,
                ),
                updateOrganization: (
                  item, {
                  required tags,
                  required folderId,
                  required clientAthleteId,
                }) =>
                    ref.read(programRepositoryProvider).updateOrganization(
                          id: item.id,
                          tags: tags,
                          folderId: folderId,
                          clientAthleteId: clientAthleteId,
                          updateClientScope: true,
                          userId: userId,
                        ),
                createFolder: (name) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.program),
                    )
                    .create(name: name, userId: userId),
                renameFolder: (folder, name) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.program),
                    )
                    .rename(folderId: folder.id, name: name, userId: userId),
                deleteFolder: (folder) => ref
                    .read(
                      libraryFolderRepositoryProvider(LibraryItemType.program),
                    )
                    .delete(folderId: folder.id, userId: userId),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => LibraryLoadError(
              message: 'Could not load folders: $error',
              onRetry: () => ref.invalidate(programFoldersProvider),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          if (browserAutomationEnabled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              markBrowserSmokeSurfaceFailure('trainer-programs', 'error');
            });
          }
          return LibraryLoadError(
            message: 'Could not load programs: $e',
            onRetry: () => ref.invalidate(programsProvider),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/programs/new'),
        tooltip: 'New program',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ProgramTile extends ConsumerWidget {
  const _ProgramTile({required this.program, required this.organizationButton});

  final Program program;
  final Widget organizationButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionLabel =
        program.currentVersion > 0 ? 'v${program.currentVersion}' : 'Draft';
    final typeLabel = program.isAssignable ? 'Assignable' : 'Personal';

    return Dismissible(
      key: Key(program.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete program?'),
            content: Text('Are you sure you want to delete "${program.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        final uid = ref.read(authStateProvider).value?.uid;
        if (uid == null) return;
        ref.read(programRepositoryProvider).softDelete(program.id, uid);
      },
      child: ListTile(
        title: Text(program.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$typeLabel · ${program.status.name} · $versionLabel'),
            if (program.tags.isNotEmpty)
              Wrap(
                spacing: 4,
                children: [
                  for (final tag in program.tags)
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            organizationButton,
            if (program.currentVersion > 0)
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy program',
                onPressed: () => _copyProgram(context, ref),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => context.push('/programs/${program.id}'),
      ),
    );
  }

  Future<void> _copyProgram(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    final repo = ref.read(programRepositoryProvider);
    try {
      final newId = await repo.copyProgram(
        sourceProgramId: program.id,
        userId: uid,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Program copied')));
        context.push('/programs/$newId?copyFrom=${program.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to copy: $e')));
      }
    }
  }
}
