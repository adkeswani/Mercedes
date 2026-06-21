import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage4/features/programs/presentation/program_providers.dart';

/// Top-level roster entry point.
///
/// Lists the coach's assignable programs; tapping one opens that program's
/// roster (where athletes are enrolled/removed). Enrollment is per-program,
/// so this screen routes the coach to the program whose roster they want to
/// manage. Personal programs are excluded — they have no enrollable athletes.
class RosterProgramsScreen extends ConsumerWidget {
  const RosterProgramsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programsAsync = ref.watch(programsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Roster')),
      body: programsAsync.when(
        data: (programs) {
          final assignable =
              programs.where((p) => p.isAssignable).toList();

          if (assignable.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No assignable programs yet. Create an assignable program '
                  'to enroll athletes.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: assignable.length,
            itemBuilder: (context, index) {
              final program = assignable[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.group, size: 32),
                  title: Text(program.name),
                  subtitle: Text(
                    program.description?.isNotEmpty == true
                        ? program.description!
                        : 'Manage enrolled athletes',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push('/programs/${program.id}/roster'),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
