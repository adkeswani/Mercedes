import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/profile/presentation/feedback_dialog.dart';
import 'package:stage5/features/profile/presentation/feedback_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

String workoutProgramLabel(String workoutName, String programName) =>
    '$workoutName - $programName';

String workoutStatusLabel(WorkoutInstanceStatus status) {
  final name = status.name;
  return '${name[0].toUpperCase()}${name.substring(1)}';
}

/// Home screen shown after authentication and onboarding.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: authenticatedAppEntryKey,
      appBar: AppBar(
        title: const Text('Mercedes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.feedback_outlined),
            tooltip: 'Send feedback',
            onPressed: () async {
              final user = ref.read(authStateProvider).value;
              final repository = ref.read(feedbackRepositoryProvider);
              if (user == null || repository == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sign in to send feedback.'),
                  ),
                );
                return;
              }

              final submitted = await showDialog<bool>(
                context: context,
                builder: (context) => FeedbackDialog(
                  onSubmit: (type, body) async {
                    await repository.submit(
                      actorId: user.uid,
                      type: type,
                      body: body,
                      appVersion: feedbackAppVersion,
                      platform: currentFeedbackPlatform(),
                      deviceModel: currentFeedbackDeviceModel(),
                      screenName: 'HomeScreen',
                    );
                  },
                ),
              );
              if (submitted == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feedback sent. Thank you!')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () {
              ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
      body: const HomeScreenContent(),
    );
  }
}

class HomeScreenContent extends ConsumerWidget {
  const HomeScreenContent({
    this.showTrainerTools = true,
    super.key,
  });

  final bool showTrainerTools;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User greeting
        authState.when(
          data: (user) => Row(
            children: [
              if (user?.photoURL != null)
                CircleAvatar(
                  radius: 24,
                  backgroundImage: NetworkImage(user!.photoURL!),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${user?.displayName ?? 'User'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      user?.email ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),

        const SizedBox(height: 24),

        // ── Dashboard section ──
        Text('Dashboard', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _TodaysWorkoutsSection(),
        const SizedBox(height: 4),
        const _MessagesPlaceholderCard(),

        if (showTrainerTools) ...[
          const SizedBox(height: 32),
          Text('Trainer Tools', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _FeatureCard(
            icon: Icons.fitness_center,
            title: 'Exercise Library',
            subtitle: 'Create and manage exercise templates',
            onTap: () => context.push('/exercises'),
          ),
          _FeatureCard(
            icon: Icons.sports_gymnastics,
            title: 'Workout Templates',
            subtitle: 'Build and publish workout templates',
            onTap: () => context.push('/workouts'),
          ),
          _FeatureCard(
            icon: Icons.folder_outlined,
            title: 'Programs',
            subtitle: 'Create programs and assign workouts',
            onTap: () => context.push('/programs'),
          ),
          _FeatureCard(
            icon: Icons.group,
            title: 'Roster',
            subtitle: 'Manage your athletes and open their calendars',
            onTap: () => context.push('/roster'),
          ),
        ],
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Placeholder for received messages until direct trainer-athlete messaging
/// ships. Mirrors the dedicated web Messages destination's placeholder copy.
class _MessagesPlaceholderCard extends StatelessWidget {
  const _MessagesPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.chat_bubble_outline, size: 32),
        title: Text('Messages'),
        subtitle: Text(
          'Trainer and athlete conversations will be available here.',
        ),
      ),
    );
  }
}

/// Shows the current user's workouts scheduled for today, with quick access
/// to open details / mark completion.
class _TodaysWorkoutsSection extends ConsumerWidget {
  String _formatIsoDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _formatIsoDate(DateTime.now());
    final scheduleAsync = ref.watch(
      athleteScheduleProvider(DateRange(startDate: today, endDate: today)),
    );

    return scheduleAsync.when(
      data: (instances) {
        if (instances.isEmpty) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.event_available, size: 32),
              title: Text('No workouts scheduled today'),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:
              instances.map((i) => _TodaysWorkoutTile(instance: i)).toList(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// A single today's-workout row that links to the completion/detail screen.
class _TodaysWorkoutTile extends ConsumerWidget {
  const _TodaysWorkoutTile({required this.instance});

  final WorkoutInstance instance;

  Color _statusColor(BuildContext context) {
    switch (instance.status) {
      case WorkoutInstanceStatus.scheduled:
        return Theme.of(context).colorScheme.primary;
      case WorkoutInstanceStatus.completed:
        return Colors.green;
      case WorkoutInstanceStatus.missed:
        return Colors.orange;
      case WorkoutInstanceStatus.cancelled:
        return Colors.grey;
    }
  }

  IconData _statusIcon() {
    switch (instance.status) {
      case WorkoutInstanceStatus.scheduled:
        return Icons.schedule;
      case WorkoutInstanceStatus.completed:
        return Icons.check_circle;
      case WorkoutInstanceStatus.missed:
        return Icons.warning_amber;
      case WorkoutInstanceStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  Future<List<String>> _loadNames(WidgetRef ref) {
    final workoutRepo = ref.watch(workoutTemplateRepositoryProvider);
    final programRepo = ref.watch(programRepositoryProvider);
    return Future.wait([
      workoutRepo
          .getById(instance.workoutTemplateId)
          .then((workout) => workout?.name ?? 'Workout'),
      programRepo
          .getById(instance.programId)
          .then((program) => program?.name ?? 'Program'),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor(context);
    final canOpen = instance.isScheduled || instance.isCompleted;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(_statusIcon(), color: color),
        title: FutureBuilder<List<String>>(
          future: _loadNames(ref),
          builder: (context, snapshot) {
            final names = snapshot.data ?? const ['Workout', 'Program'];
            return Text(workoutProgramLabel(names[0], names[1]));
          },
        ),
        subtitle: Text(workoutStatusLabel(instance.status)),
        trailing: instance.isScheduled
            ? FilledButton(
                onPressed: () =>
                    context.push('/athlete/workouts/${instance.id}'),
                child: const Text('Complete'),
              )
            : const Icon(Icons.chevron_right),
        onTap: canOpen
            ? () => context.push('/athlete/workouts/${instance.id}')
            : null,
      ),
    );
  }
}

