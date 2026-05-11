import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage2/features/auth/presentation/auth_providers.dart';
import 'package:stage2/features/programs/domain/program.dart';
import 'package:stage2/features/programs/presentation/program_providers.dart';

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
          return ListView.builder(
            itemCount: programs.length,
            itemBuilder: (context, index) {
              final program = programs[index];
              return _ProgramTile(program: program);
            },
          );
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
