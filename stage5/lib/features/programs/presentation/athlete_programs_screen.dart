import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';
import 'package:stage5/features/programs/presentation/athlete_program_instance_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';

class AthleteProgramsScreen extends ConsumerWidget {
  const AthleteProgramsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(myAthleteProgramInstancesProvider);
    final backfill =
        ref.watch(myAthleteProgramInstanceBackfillStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My programs')),
      body: instances.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Unable to load your programs: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            if (backfill.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (backfill.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to import legacy program assignments: '
                    '${backfill.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No program instances yet. Programs assigned to you will '
                  'appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              if (backfill.hasError)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Some legacy program assignments could not be imported: '
                    '${backfill.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _AthleteProgramCard(instance: items[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AthleteProgramCard extends ConsumerWidget {
  const _AthleteProgramCard({required this.instance});

  final AthleteProgramInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program =
        ref.watch(programRepositoryProvider).getById(instance.sourceProgramId);
    return FutureBuilder(
      future: program,
      builder: (context, snapshot) {
        if (browserSmokeConfig.autoLoginEnabled && snapshot.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            markBrowserSmokeSurfaceReady('athlete-programs');
          });
        }
        final title = snapshot.connectionState != ConnectionState.done
            ? 'Loading program...'
            : snapshot.data?.name ?? 'Program details unavailable';
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            button: true,
            label: '$title, ${_label(instance.status)}',
            child: ListTile(
              leading: const Icon(Icons.school_outlined, size: 32),
              title: Text(title),
              subtitle: Text(
                '${_label(instance.status)} · '
                '${instance.startDate} to ${instance.expectedEndDate}\n'
                '${instance.workoutCount} workouts · '
                'version ${instance.sourceProgramVersion}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                '/programs/${instance.sourceProgramId}/athlete/'
                '${instance.athleteOwnerId}',
              ),
            ),
          ),
        );
      },
    );
  }

  static String _label(Object value) {
    final name = value.toString().split('.').last;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }
}
