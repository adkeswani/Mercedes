import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/features/auth/presentation/auth_providers.dart';
import 'package:stage4/features/programs/domain/program.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';

/// Displays the user's program library.
class ProgramListScreen extends ConsumerWidget {
  const ProgramListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programsAsync = ref.watch(programsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Programs'),
      ),
      body: programsAsync.when(
        data: (programs) {
          if (programs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No programs yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first program'),
                ],
              ),
            );
          }
          final folders = ref.watch(programFoldersProvider).valueOrNull ?? [];
          return _buildGroupedList(context, programs, folders);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/programs/new'),
        tooltip: 'New program',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Groups programs under their folders, with an "Ungrouped" section last.
  Widget _buildGroupedList(
    BuildContext context,
    List<Program> programs,
    List<ProgramFolder> folders,
  ) {
    final folderById = {for (final f in folders) f.id: f};
    final grouped = <String?, List<Program>>{};
    for (final p in programs) {
      final key = folderById.containsKey(p.folderId) ? p.folderId : null;
      grouped.putIfAbsent(key, () => []).add(p);
    }

    final sortedFolders = [...folders]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final items = <Widget>[];
    for (final folder in sortedFolders) {
      final progs = grouped[folder.id] ?? const [];
      items.add(_FolderHeader(folder: folder, count: progs.length));
      for (final p in progs) {
        items.add(_ProgramTile(program: p));
      }
    }

    final ungrouped = grouped[null] ?? const [];
    if (ungrouped.isNotEmpty) {
      if (sortedFolders.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Ungrouped',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
      for (final p in ungrouped) {
        items.add(_ProgramTile(program: p));
      }
    }
    return ListView(children: items);
  }
}

/// Section header for a program folder with rename/delete actions.
class _FolderHeader extends ConsumerWidget {
  const _FolderHeader({required this.folder, required this.count});

  final ProgramFolder folder;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.folder, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${folder.name} ($count)',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') {
                _rename(context, ref);
              } else if (value == 'delete') {
                _delete(context, ref);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(programFolderRepositoryProvider).rename(
          folderId: folder.id,
          name: name.trim(),
          userId: uid,
        );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete folder?'),
        content: const Text(
          'Programs in this folder will be moved to Ungrouped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(programFolderRepositoryProvider).delete(
          folderId: folder.id,
          userId: uid,
        );
  }
}

class _ProgramTile extends ConsumerWidget {
  const _ProgramTile({required this.program});

  final Program program;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionLabel = program.currentVersion > 0
        ? 'v${program.currentVersion}'
        : 'Draft';
    final typeLabel = program.isAssignable ? 'Assignable' : 'Personal';

    return Dismissible(
      key: Key(program.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: Icon(
          Icons.delete,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete program?'),
            content: Text(
              'Are you sure you want to delete "${program.name}"?',
            ),
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
        subtitle: Text('$typeLabel · ${program.status.name} · $versionLabel'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Program copied')),
        );
        context.push('/programs/$newId?copyFrom=${program.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to copy: $e')),
        );
      }
    }
  }
}
