import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';
import 'package:stage5/features/programs/presentation/athlete_program_instance_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/relationships/domain/trainer_client_workspace.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_workspace_providers.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';
import 'package:stage5/features/trainer_dashboard/presentation/trainer_dashboard_providers.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_instance_labels.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

/// One-client hub for trainers: pick a client from the roster dropdown, then
/// browse their schedule, programs, independent workouts, and activity
/// without leaving the page.
///
/// Create/edit/assignment workflows remain on their existing screens; this
/// hub is a read-only overview (see `docs/remaining-features.md`).
class TrainerClientWorkspaceScreen extends ConsumerStatefulWidget {
  const TrainerClientWorkspaceScreen({super.key});

  @override
  ConsumerState<TrainerClientWorkspaceScreen> createState() =>
      _TrainerClientWorkspaceScreenState();
}

class _TrainerClientWorkspaceScreenState
    extends ConsumerState<TrainerClientWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: ClientWorkspaceTab.values.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relationshipsAsync = ref.watch(trainerClientsProvider);
    final namesAsync = ref.watch(activeTrainerClientNamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Manage roster',
            onPressed: () => context.push('/roster'),
          ),
        ],
      ),
      body: relationshipsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (browserAutomationEnabled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              markBrowserSmokeSurfaceFailure('trainer-clients', 'error');
            });
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load your roster: $error',
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
        data: (relationships) {
          final athleteIds =
              {for (final r in relationships) r.athleteId}.toList();
          if (athleteIds.isEmpty) {
            if (browserAutomationEnabled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                markBrowserSmokeSurfaceFailure('trainer-clients', 'empty');
              });
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No athletes on your roster yet. Use "Manage roster" to '
                  'add a client.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final names = namesAsync.valueOrNull ?? const <String, String>{};
          final selected = ref.watch(selectedWorkspaceAthleteIdProvider);
          final current = (selected != null && athleteIds.contains(selected))
              ? selected
              : athleteIds.first;

          if (current != selected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ref.read(selectedWorkspaceAthleteIdProvider.notifier).state =
                  current;
            });
          }

          if (browserAutomationEnabled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              markBrowserSmokeSurfaceReady(
                'trainer-clients',
                content: names[current] ?? current,
              );
            });
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: DropdownButtonFormField<String>(
                  initialValue: current,
                  decoration: const InputDecoration(labelText: 'Client'),
                  items: athleteIds
                      .map(
                        (id) => DropdownMenuItem(
                          value: id,
                          child: Text(names[id] ?? id),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(selectedWorkspaceAthleteIdProvider.notifier)
                        .state = value;
                  },
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  for (final tab in ClientWorkspaceTab.values)
                    Tab(text: clientWorkspaceTabLabel(tab)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    for (final tab in ClientWorkspaceTab.values)
                      _WorkspaceTabBody(tab: tab, athleteId: current),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WorkspaceTabBody extends ConsumerWidget {
  const _WorkspaceTabBody({required this.tab, required this.athleteId});

  final ClientWorkspaceTab tab;
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (tab) {
      ClientWorkspaceTab.all => _AllTab(athleteId: athleteId),
      ClientWorkspaceTab.schedule => _ScheduleTab(athleteId: athleteId),
      ClientWorkspaceTab.programs => _ProgramsTab(athleteId: athleteId),
      ClientWorkspaceTab.workouts => _WorkoutsTab(athleteId: athleteId),
      ClientWorkspaceTab.activity => _ActivityTab(athleteId: athleteId),
    };
  }
}

/// Lightweight overview combining counts from the other tabs.
class _AllTab extends ConsumerWidget {
  const _AllTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(clientWorkspaceScheduleProvider);
    final programsAsync = ref.watch(managedAthleteProgramInstancesProvider);
    final activityAsync = ref.watch(trainerDashboardProvider);

    final schedule = scheduleAsync.valueOrNull ?? const <WorkoutInstance>[];
    final programs = filterProgramInstancesForAthlete(
      programsAsync.valueOrNull ?? const <AthleteProgramInstance>[],
      athleteId,
    );
    final independentWorkouts = filterIndependentWorkouts(schedule);
    final activity = filterActivityEventsForAthlete(
      activityAsync.valueOrNull?.events ?? const <TrainerActivityEvent>[],
      athleteId,
    );

    final isLoading = scheduleAsync.isLoading ||
        programsAsync.isLoading ||
        activityAsync.isLoading;
    if (isLoading &&
        schedule.isEmpty &&
        programs.isEmpty &&
        activity.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryCard(
          icon: Icons.calendar_month_outlined,
          label: 'Scheduled workouts (next ${clientWorkspaceScheduleLookaheadDays}d / '
              'last ${clientWorkspaceScheduleLookbackDays}d)',
          count: schedule.length,
        ),
        _SummaryCard(
          icon: Icons.school_outlined,
          label: 'Active and past programs',
          count: programs.length,
        ),
        _SummaryCard(
          icon: Icons.fitness_center_outlined,
          label: 'Independent workouts in window',
          count: independentWorkouts.length,
        ),
        _SummaryCard(
          icon: Icons.notifications_outlined,
          label: 'Recent activity',
          count: activity.length,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(
          '$count',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}

class _ScheduleTab extends ConsumerWidget {
  const _ScheduleTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(clientWorkspaceScheduleProvider);
    return scheduleAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Unable to load schedule: $error'),
      ),
      data: (instances) {
        if (instances.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No workouts scheduled in this window.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final sorted = [...instances]
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          itemBuilder: (context, index) =>
              _WorkoutInstanceTile(instance: sorted[index]),
        );
      },
    );
  }
}

class _WorkoutsTab extends ConsumerWidget {
  const _WorkoutsTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(clientWorkspaceScheduleProvider);
    return scheduleAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Unable to load workouts: $error'),
      ),
      data: (instances) {
        final independent = filterIndependentWorkouts(instances)
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
        if (independent.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No independent workouts in this window.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: independent.length,
          itemBuilder: (context, index) =>
              _WorkoutInstanceTile(instance: independent[index]),
        );
      },
    );
  }
}

class _WorkoutInstanceTile extends ConsumerWidget {
  const _WorkoutInstanceTile({required this.instance});

  final WorkoutInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref
        .watch(workoutTemplateRepositoryProvider)
        .getById(instance.workoutTemplateId);
    final status = workoutStatusLabel(instance.status);
    return FutureBuilder(
      future: template,
      builder: (context, snapshot) {
        final title = snapshot.connectionState != ConnectionState.done
            ? 'Loading workout...'
            : snapshot.data?.name ?? 'Workout details unavailable';
        return Card(
          child: ListTile(
            leading: Icon(
              instance.isCompleted
                  ? Icons.check_circle
                  : Icons.schedule_outlined,
              color: instance.isCompleted ? Colors.green : null,
            ),
            title: Text(title),
            subtitle: Text('${instance.scheduledDate} · $status'),
          ),
        );
      },
    );
  }
}

class _ProgramsTab extends ConsumerWidget {
  const _ProgramsTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programsAsync = ref.watch(managedAthleteProgramInstancesProvider);
    return programsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Unable to load programs: $error'),
      ),
      data: (instances) {
        final mine = filterProgramInstancesForAthlete(instances, athleteId)
          ..sort((a, b) => b.startDate.compareTo(a.startDate));
        if (mine.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No programs assigned to this client yet.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: mine.length,
          itemBuilder: (context, index) =>
              _ProgramInstanceTile(instance: mine[index]),
        );
      },
    );
  }
}

class _ProgramInstanceTile extends ConsumerWidget {
  const _ProgramInstanceTile({required this.instance});

  final AthleteProgramInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program =
        ref.watch(programRepositoryProvider).getById(instance.sourceProgramId);
    return FutureBuilder(
      future: program,
      builder: (context, snapshot) {
        final title = snapshot.connectionState != ConnectionState.done
            ? 'Loading program...'
            : snapshot.data?.name ?? 'Program details unavailable';
        return Card(
          child: ListTile(
            leading: const Icon(Icons.school_outlined),
            title: Text(title),
            subtitle: Text(
              '${_statusLabel(instance.status)} · '
              '${instance.startDate} to ${instance.expectedEndDate}\n'
              '${instance.workoutCount} workouts',
            ),
            isThreeLine: true,
            onTap: () => context.push(
              '/programs/${instance.sourceProgramId}/athlete/'
              '${instance.athleteOwnerId}',
            ),
          ),
        );
      },
    );
  }

  static String _statusLabel(Object value) {
    final name = value.toString().split('.').last;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }
}

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(trainerDashboardProvider);
    return activityAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Unable to load activity: $error'),
      ),
      data: (page) {
        final events = filterActivityEventsForAthlete(page.events, athleteId)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        if (events.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No recent activity for this client.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: events.length,
          itemBuilder: (context, index) =>
              _ActivityEventTile(event: events[index]),
        );
      },
    );
  }
}

class _ActivityEventTile extends StatelessWidget {
  const _ActivityEventTile({required this.event});

  final TrainerActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _describe(event);
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  (String, String) _describe(TrainerActivityEvent event) {
    if (event is CompletionActivityEvent) {
      return ('Completed ${event.workoutName}', _timestamp(event.occurredAt));
    }
    if (event is CommentActivityEvent) {
      return (
        '${event.authorName} commented',
        '${event.comment}\n${_timestamp(event.occurredAt)}',
      );
    }
    if (event is ReactionActivityEvent) {
      return (
        '${event.actorName} reacted',
        _timestamp(event.occurredAt),
      );
    }
    if (event is ProgramEndingSoonActivityEvent) {
      return (
        '${event.programName} ends soon',
        '${event.daysRemaining} days remaining · ${_timestamp(event.occurredAt)}',
      );
    }
    if (event is PersonalBestActivityEvent) {
      return (event.summary, _timestamp(event.occurredAt));
    }
    return ('Activity', _timestamp(event.occurredAt));
  }

  String _timestamp(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
