import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage4/features/programs/domain/program.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';

/// Read-only overview of a program available to an enrolled athlete.
class AthleteProgramOverviewScreen extends ConsumerWidget {
  const AthleteProgramOverviewScreen({
    super.key,
    required this.programId,
  });

  final String programId;

  Future<({Program? program, List<ProgramScheduleEntry> entries})> _load(
    WidgetRef ref,
  ) async {
    final repo = ref.read(programRepositoryProvider);
    final program = await repo.getById(programId);
    final entries = await repo.getLatestEntries(programId);
    return (program: program, entries: entries);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: _load(ref),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final program = data?.program;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || program == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Program')),
            body: Center(
              child: Text(
                snapshot.hasError
                    ? 'Unable to load program: ${snapshot.error}'
                    : 'Program unavailable',
              ),
            ),
          );
        }

        final entries = [...data!.entries]..sort((a, b) {
            final byDay = a.dayOffset.compareTo(b.dayOffset);
            return byDay != 0 ? byDay : a.sortOrder.compareTo(b.sortOrder);
          });

        return Scaffold(
          appBar: AppBar(title: Text(program.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (program.description?.isNotEmpty ?? false) ...[
                Text(
                  program.description!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
              ],
              Text(
                'Published schedule',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.event_busy),
                    title: Text('No workouts published'),
                  ),
                )
              else
                ...entries.map(
                  (entry) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text('${entry.dayOffset + 1}'),
                      ),
                      title: Text(entry.workoutName ?? 'Workout'),
                      subtitle: Text('Day ${entry.dayOffset + 1}'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
