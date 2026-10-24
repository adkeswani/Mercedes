import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/features/athlete_dashboard/presentation/athlete_dashboard_view.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/profile/presentation/feedback_dialog.dart';
import 'package:stage5/features/profile/presentation/feedback_providers.dart';

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
        const AthleteDashboardView(),

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
